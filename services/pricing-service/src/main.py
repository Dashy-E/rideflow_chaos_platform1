"""pricing-service — fare computation with a deliberately CPU-bound surge
Monte Carlo simulation, so HPA scale-out is easy to trigger for CO3 demos.
"""
import asyncio
import os
import random
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from prometheus_client import Counter, Histogram, Gauge, CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel

SERVICE = "pricing-service"
PORT = int(os.getenv("PORT", "8084"))
REGION = os.getenv("REGION", "local")

REQS = Counter("http_requests_total", "requests", ["service", "method", "route", "code"])
DUR = Histogram("http_request_duration_seconds", "latency", ["service", "method", "route"])
INFLIGHT = Gauge("http_requests_in_flight", "in flight", ["service"])
SURGE = Gauge("surge_multiplier", "current surge multiplier")

BASE_FARE = 40.0
PER_KM = 12.0
PER_MIN = 1.5

# a rolling counter of "open requests" vs "available drivers" fed by the caller,
# used only to make the surge formula respond to load in demos
_state = {"open_requests": 3, "available_drivers": 10}


def monte_carlo_demand_factor(samples: int = 20000) -> float:
    """Deliberately CPU-bound: simulate demand noise so a sustained request
    rate visibly drives CPU utilization high enough to trigger the HPA."""
    total = 0.0
    for _ in range(samples):
        total += random.random() ** 2
    return total / samples


class QuoteRequest(BaseModel):
    distance_km: float
    eta_min: float
    open_requests: int | None = None
    available_drivers: int | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(lifespan=lifespan)
_runtime_fault = {"mode": os.getenv("CHAOS_INJECT", "")}


@app.patch("/admin/chaos")
def set_chaos(mode: str = ""):
    """mode: '' | 'latency' | 'error' — set by the chaos injector at runtime,
    so faults can be toggled without a Kubernetes control plane (local demos)."""
    _runtime_fault["mode"] = mode
    return {"mode": mode}


@app.middleware("http")
async def metrics_and_chaos(request: Request, call_next):
    INFLIGHT.labels(SERVICE).inc()
    start = time.time()
    # /admin/chaos must never be affected by the fault it itself controls —
    # otherwise setting mode=error makes the toggle permanently unreachable
    if request.url.path == "/admin/chaos":
        response = await call_next(request)
        INFLIGHT.labels(SERVICE).dec()
        DUR.labels(SERVICE, request.method, request.url.path).observe(time.time() - start)
        REQS.labels(SERVICE, request.method, request.url.path, str(response.status_code)).inc()
        return response
    fault = request.headers.get("x-chaos-fault") or _runtime_fault["mode"]
    if fault == "latency":
        # must not block: time.sleep here stalled the whole event loop, so under
        # load even /admin/chaos (the revert) queued behind the injected delay
        await asyncio.sleep(float(os.getenv("CHAOS_LATENCY_MS", "300")) / 1000)
    elif fault == "error":
        INFLIGHT.labels(SERVICE).dec()
        REQS.labels(SERVICE, request.method, request.url.path, "500").inc()
        return Response(status_code=500, content="chaos-injected error")
    try:
        response = await call_next(request)
    finally:
        INFLIGHT.labels(SERVICE).dec()
    DUR.labels(SERVICE, request.method, request.url.path).observe(time.time() - start)
    REQS.labels(SERVICE, request.method, request.url.path, str(response.status_code)).inc()
    return response


@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": SERVICE, "region": REGION}


@app.get("/readyz")
def readyz():
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/internal/quote")
def quote(req: QuoteRequest):
    if req.open_requests is not None:
        _state["open_requests"] = req.open_requests
    if req.available_drivers is not None:
        _state["available_drivers"] = max(1, req.available_drivers)

    demand_noise = monte_carlo_demand_factor()
    ratio = _state["open_requests"] / _state["available_drivers"] - 1
    surge = max(1.0, min(3.0, 1.0 + 0.4 * ratio + 0.05 * (demand_noise - 0.33)))
    SURGE.set(surge)

    fare = (BASE_FARE + req.distance_km * PER_KM + req.eta_min * PER_MIN) * surge
    return {"fare": round(fare, 2), "surge": round(surge, 2), "fareEstimated": False}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
