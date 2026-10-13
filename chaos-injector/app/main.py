import glob
import logging
import os
import random
import time
from contextlib import asynccontextmanager

import httpx
import yaml
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import BackgroundTasks, FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from .backends import SERVICE_URLS, build_backend
from .engine import ChaosEngine, SafetyError
from .metrics import ChaosMetrics
from .models import ExperimentDefinition

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper())
logger = logging.getLogger("chaos.main")

EXPERIMENTS_DIR = os.getenv("EXPERIMENTS_DIR", "/app/experiments")
PORT = int(os.getenv("PORT", "9000"))

metrics = ChaosMetrics()
backend = build_backend()
engine = ChaosEngine(backend, metrics)
scheduler = AsyncIOScheduler()

EXPERIMENTS: dict[str, ExperimentDefinition] = {}


def load_experiments() -> dict[str, ExperimentDefinition]:
    found = {}
    for path in glob.glob(os.path.join(EXPERIMENTS_DIR, "*.yaml")) + glob.glob(os.path.join(EXPERIMENTS_DIR, "*.yml")):
        try:
            raw = yaml.safe_load(open(path))
            if raw.get("fault", {}).get("type") not in (
                "pod_kill", "cpu_hog", "network_latency", "oom",
                "az_blackhole", "region_failure", "dependency_failure", "packet_loss",
            ):
                logger.info("skipping %s (not a single-fault experiment definition, e.g. game-day)", path)
                continue
            exp = ExperimentDefinition(**raw)
            found[exp.id] = exp
        except Exception as e:
            logger.warning("failed to load experiment %s: %s", path, e)
    logger.info("loaded %d experiment definitions", len(found))
    return found


@asynccontextmanager
async def lifespan(app: FastAPI):
    global EXPERIMENTS
    EXPERIMENTS = load_experiments()
    orphan = engine.find_orphaned_fault()
    if orphan:
        logger.warning("found orphaned active fault from a previous crash: %s — reverting", orphan)
        result = await engine.recover_orphaned_fault(EXPERIMENTS)
        logger.warning("crash recovery: %s", result)
    scheduler.start()
    yield
    scheduler.shutdown(wait=False)


app = FastAPI(title="RideFlow Chaos Injector", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": "chaos-injector"}


@app.get("/readyz")
def readyz():
    return {"status": "ready", "backend": type(backend).__name__}


@app.get("/metrics")
def metrics_endpoint():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/experiments")
def list_experiments():
    return [e.model_dump() for e in EXPERIMENTS.values()]


@app.post("/experiments/{experiment_id}/run")
async def run_experiment(experiment_id: str, dryRun: bool = False):
    exp = EXPERIMENTS.get(experiment_id)
    if not exp:
        raise HTTPException(404, f"unknown experiment {experiment_id}")
    try:
        run = await engine.run_experiment(exp, dry_run=dryRun)
    except SafetyError as e:
        raise HTTPException(409, str(e))
    if run.mttdSeconds is not None:
        metrics.mttd.labels(exp.id).set(run.mttdSeconds)
    if run.mttrSeconds is not None:
        metrics.mttr.labels(exp.id).set(run.mttrSeconds)
    return run.model_dump()


@app.get("/runs")
def list_runs():
    return [r.model_dump() for r in engine.list_runs()]


@app.get("/runs/{run_id}")
def get_run(run_id: str):
    run = engine.get_run(run_id)
    if not run:
        raise HTTPException(404, "run not found")
    return run.model_dump()


@app.post("/abort")
async def abort():
    result = await engine.abort_all(EXPERIMENTS)
    return {"aborted": True, "detail": result}


async def _game_day_tick():
    if not engine.enabled or engine.is_running():
        return
    candidates = list(EXPERIMENTS.values())
    if not candidates:
        return
    exp = random.choice(candidates)
    logger.info("game-day: running %s", exp.id)
    try:
        await engine.run_experiment(exp)
    except SafetyError as e:
        logger.info("game-day: skipped (%s)", e)


@app.post("/schedule")
def enable_schedule(interval_seconds: int = 300):
    engine.set_enabled(True)
    scheduler.remove_all_jobs()
    scheduler.add_job(_game_day_tick, "interval", seconds=interval_seconds, id="game-day")
    return {"scheduled": True, "intervalSeconds": interval_seconds}


@app.delete("/schedule")
def disable_schedule():
    scheduler.remove_all_jobs()
    return {"scheduled": False}


@app.post("/kill-switch")
def kill_switch(enabled: bool):
    engine.set_enabled(enabled)
    if not enabled:
        scheduler.remove_all_jobs()
    return {"enabled": engine.enabled}


@app.get("/metrics/summary")
async def metrics_summary():
    """Aggregated numbers for the dashboard's Overview tab — queried
    server-side so the browser never has to talk to Prometheus directly
    (avoids CORS entirely)."""
    queries = {
        "rps": 'sum(rate(http_requests_total{job="api-gateway"}[1m]))',
        "errorRate": 'sum(rate(http_requests_total{job="api-gateway",code=~"5.."}[1m])) / clamp_min(sum(rate(http_requests_total{job="api-gateway"}[1m])), 1e-9)',
        "p99LatencyMs": 'histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{job="api-gateway"}[1m])) by (le)) * 1000',
        "ridesPerMin": "sum(rate(rides_created_total[1m])) * 60",
    }
    out = {}
    async with httpx.AsyncClient(timeout=3.0) as c:
        for key, q in queries.items():
            try:
                r = await c.get(f"{os.getenv('PROMETHEUS_URL', 'http://prometheus:9090')}/api/v1/query", params={"query": q})
                result = r.json()["data"]["result"]
                val = float(result[0]["value"][1]) if result else 0.0
                out[key] = None if val != val else round(val, 3)  # NaN -> null
            except Exception:
                out[key] = None
    return out


@app.get("/status")
async def status():
    """One-call summary for the live dashboard: injector state + a quick
    health probe of every downstream service."""
    health = {}
    async with httpx.AsyncClient(timeout=1.5) as c:
        for name, url in SERVICE_URLS.items():
            try:
                r = await c.get(f"{url}/healthz")
                health[name] = r.status_code == 200
            except Exception:
                health[name] = False
    recent = engine.list_runs()[:10]
    return {
        "enabled": engine.enabled,
        "backend": type(backend).__name__,
        "activeRun": engine._active_run.model_dump() if engine._active_run else None,
        "serviceHealth": health,
        "recentRuns": [r.model_dump() for r in recent],
        "experimentCount": len(EXPERIMENTS),
        "timestamp": time.time(),
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
