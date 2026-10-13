# RideFlow — Project Handoff & Continuation Guide

**Read this file first, before anything else in the repo.** It's written for whoever (human or AI) picks this project up next — it tells you exactly what exists, what's verified working, what's still missing, and what to do about each gap. The original project brief is [RideFlow-Chaos-Platform-Documentation.md](RideFlow-Chaos-Platform-Documentation.md) — that's the *spec*; this file is the *status report + continuation plan* against that spec.

---

## 0. One-paragraph orientation

RideFlow is a ride-hailing backend (5 microservices) built specifically to be broken on purpose. Two engines run against it: a **chaos injector** that kills pods, cuts dependencies, and simulates regional outages while measuring recovery time (MTTD/MTTR), and a **security attack simulator** that red-teams the app's own auth, JWT handling, input validation, and access control. Both are driven from one live dashboard. Everything above is **fully built and verified working locally** (see §2). What's missing is (a) a real cloud deployment and (b) the actual research output — running the experiment matrix for real, collecting evidence, and writing the paper. That's the work left in §3–§4.

---

## 1. Where things are, physically

```
RideFlow-Chaos-Platform/
├── HANDOFF.md                              <- you are here
├── RideFlow-Chaos-Platform-Documentation.md <- original 18-section spec/brief
├── README.md                                <- quickstart + feature tour
├── docker-compose.yml                       <- the whole local stack, one command
├── Makefile                                 <- up/down/load-test/chaos-demo/security-demo
├── services/                                <- 5 microservices (Go/Node/Python)
├── chaos-injector/                          <- fault injection + MTTD/MTTR engine
├── security-injector/                       <- authorized attack simulator
├── attacks/                                 <- 6 security attack definitions (YAML)
├── experiments/                             <- 9 chaos experiment definitions (YAML)
├── frontend/dist/index.html                 <- Mission Control dashboard (single file, no build step)
├── observability/                           <- Prometheus rules, Grafana provisioning
├── dashboards/                               <- 3 Grafana dashboard JSON files
├── loadtest/                                <- k6 scripts
├── infra/
│   ├── modules/, envs/, global/             <- FULL multi-region EKS Terraform (written, NEVER applied)
│   └── free-tier-ec2/                       <- single free-tier EC2 Terraform (written, validated, NEVER applied)
├── deploy/helm/rideflow/                    <- Helm chart for the EKS path
├── docs/
│   ├── api/contracts.md                     <- authoritative ports/endpoints/env vars — read before touching any service
│   ├── adr/0001–0006                        <- architecture decision records
│   ├── runbooks/                            <- deploy/rollback/failover/chaos-abort/teardown
│   └── security/baseline-findings.md        <- first full security-attack run results
└── .github/workflows/                       <- CI + CD pipelines (written, never run against a real GitHub Actions instance)
```

---

## 2. What's DONE and verified (do not re-do this)

### 2.1 Application layer — fully working
All 5 services (api-gateway/Go, user-service/Node, ride-service/Python, driver-service/Go, pricing-service/Python) implement their full contract from `docs/api/contracts.md`: health/ready/metrics endpoints, the ride lifecycle state machine, circuit breakers, both documented degradation paths (pricing down → cached fare; driver down → `PENDING_MATCH` + background retry). Verified end-to-end: register → login → create ride → match → get → cancel, all through the real gateway.

### 2.2 Chaos engine — fully working
`chaos-injector/` implements the full doc §8.3 lifecycle (ValidateHypothesis → CheckBlastRadius → InjectFault → Monitor → Revert → MeasureRecovery → EmitReport) against **either** a real Kubernetes cluster **or** the local docker-compose stack (`app/backends.py` — `KubernetesBackend` / `LocalBackend`). All 8 fault types from the catalogue (pod_kill, cpu_hog, oom, dependency_failure, network_latency, packet_loss, az_blackhole, region_failure) are implemented for both backends. Verified with a real run: injected a dependency failure, watched it detect the breach, auto-revert, and report a real MTTR (120.7s) — annotations posted to Grafana correctly.

Safety controls actually implemented and tested, not just described: global kill switch, concurrency limit of 1, namespace/service denylist, dry-run mode, and **crash recovery** — verified by actually SIGKILLing the injector mid-fault and confirming it found the orphaned state and self-healed the target service on restart.

### 2.3 Security engine — fully working
`security-injector/` runs 6 attack modules against the app's own services only (hardcoded targets, not parameterizable — this is what keeps it "authorized self-testing" rather than a general attack tool): `auth_bruteforce`, `rate_limit_pressure`, `jwt_tampering`, `injection_fuzz`, `idor_probe`, `internal_endpoint_recon`. Current baseline results (deterministic, reproduced across multiple full rebuilds) are in `docs/security/baseline-findings.md`:

| Attack | Verdict |
|---|---|
| rate-limit-pressure-gateway | ✅ defended |
| injection-fuzz-ride-service | ✅ defended |
| jwt-tampering-user-service | ⚠️ partial (forged-token-with-default-secret finding) |
| auth-bruteforce-user-service | ⚠️ partial (no account lockout) |
| idor-probe-ride-service | ❌ vulnerable (no per-ride ownership check + no service-to-service auth) |
| internal-endpoint-recon | ❌ vulnerable (expected in this topology, verify differently once on AWS) |

**This tool already found and led to fixing one real bug** during development: the gateway's rate limiter keyed on `RemoteAddr` (host:port) instead of just the host, so every request got a fresh bucket and rate limiting never engaged. Fixed in `services/api-gateway/main.go`. This before/after is a strong, honest artifact for the research paper — the security tool proved its own value against this exact codebase.

### 2.4 Dashboard — fully working
`frontend/dist/index.html`, served at `:5173`. Four tabs: Overview (live topology diagram, RPS/error-rate/p99/rides-per-min stat cards pulled server-side from Prometheus via `chaos-injector`'s `/metrics/summary` endpoint — avoids CORS), Chaos Engineering, Security Testing, Live Logs. No build step, no framework — plain HTML/CSS/JS polling both engines' REST APIs every 2s. Verified rendering correctly via actual browser screenshots during testing, including live fault-in-progress state.

### 2.5 Observability — fully working
Prometheus (3 targets... actually 8 scrape targets, all healthy), 4 recording rules, 7 alert rules, 3 Grafana dashboards (Platform Overview, Chaos Timeline, Recovery Analysis) — all provisioned automatically on startup, all verified loading with real panels via the Grafana API, not just "the JSON file exists."

### 2.6 A full session of adversarial testing already happened
A complete clean-slate rebuild + systematic walkthrough was done specifically to find bugs before handoff. **6 real bugs were found and fixed** — this is worth citing directly in the research paper as evidence of the platform's own value:

1. Prometheus/Grafana healthcheck grace periods too short for cold-volume starts → fixed (`docker-compose.yml`)
2. Grafana's plugin-update-check calls stalling on restricted networks → disabled via env vars
3. **`/admin/chaos` toggle self-locking** in ride-service/pricing-service — once broken, could never be un-broken via the API itself (FastAPI middleware wraps all routes unconditionally, unlike the Node/Go services where route order mattered) → fixed
4. **ride-service never implemented `error` fault mode**, only `latency` — dependency-failure faults against it were silently no-ops → fixed
5. **Grafana annotations were silently failing** — anonymous access is read-only and the code never checked the response status → fixed with real auth + `raise_for_status()`
6. **Crash-recovery didn't actually work on a real crash** — only on a graceful in-process abort, since the revert function lived in memory only → redesigned to persist recovery state *before* injecting, and rewrote startup recovery to reconstruct the revert from disk + reloaded experiment definitions, not an in-memory lambda. Verified with an actual SIGKILL test.

### 2.7 Infrastructure — written but NOT applied (see §3)
- Full multi-region EKS Terraform (`infra/modules/`, `infra/envs/`, `infra/global/`) — syntactically validated only, never run against real AWS.
- Free-tier single-EC2 Terraform (`infra/free-tier-ec2/`) — `terraform init` + `terraform validate` both pass. Never applied.
- Helm chart (`deploy/helm/rideflow/`) — never installed against a real cluster.
- GitHub Actions workflows (`.github/workflows/`) — never run against a real GitHub Actions runner.

### 2.8 Tooling installed on the dev machine
AWS CLI, Terraform, Helm, GitHub CLI (`gh`) are all installed. **AWS credentials are NOT configured** (`aws configure` was never run — that's a step only the account owner can do). **GitHub CLI is NOT authenticated** (`gh auth login` needs to be run interactively by whoever owns the GitHub account this pushes to).

---

## 3. What's NOT done — the actual remaining work

### 3.1 Real cloud deployment (nothing has been deployed to AWS yet)
Two paths exist, pick one based on budget:

**Path A — free-tier EC2 (recommended if budget is $0):**
```bash
aws configure              # you do this — needs an AWS account + access key
cd infra/free-tier-ec2
terraform init
terraform apply            # ~3-5 min, prints a public dashboard URL
```
Full instructions and cost caveats: `infra/free-tier-ec2/README.md`. **Before running `apply`**: check AWS Console → Billing → Free Tier to confirm the account is actually within its free-tier window, and set a budget alarm (doc §14.3) regardless.

**Path B — full multi-region EKS (matches the original spec exactly, costs real money):**
Follow `docs/runbooks/deploy.md` "AWS (primary region)" then "(secondary region)" sections, applying `infra/global` → `infra/envs/primary` → `infra/envs/secondary` in that order. Budget ~$60-100 for the whole project lifetime if you follow the cost discipline in doc §14.2-14.3 (spot instances, scheduled teardown, single NAT). This path is what unlocks the CO3/CO5 evidence the original spec cares about (real HPA scale-out, real ALB, real Route 53 failover) — Path A cannot produce that evidence since there's no Kubernetes involved at all.

**Either way**, once deployed: re-run the security-injector's `internal-endpoint-recon` attack against the real deployment — locally it's "vulnerable by expected construction" (everything's on the host), but on real infrastructure this becomes a genuine finding either way and is good report material.

### 3.2 The actual experiment matrix has never been run
Doc §13.2 defines 9 experiments (E1-E9), each requiring **multiple runs** (5x for most, 3x for the disruptive ones, 1x for the 60-minute game day) with results recorded in the §13.3 table. **Zero of these formal runs have happened** — everything verified in §2.2 was ad-hoc functional testing, not the structured evaluation the report needs. To do this:

1. Deploy (§3.1, either path — but Path B strongly preferred here, since E6/E7 need real AZs/regions to mean anything).
2. Start steady load: `make load-test` (needs k6 installed, or run via `docker run -v $(pwd)/loadtest:/scripts grafana/k6 run /scripts/steady-state.js`).
3. For each experiment ID in `experiments/*.yaml`, run it the required number of times: `curl -X POST $CHAOS_URL/experiments/<id>/run`, record MTTD/MTTR/peak-error-rate/p99 from each run's result and from the Grafana Chaos Timeline dashboard.
4. Fill in doc §13.3's results table with real numbers (mean ± standard deviation across the 5 runs, per doc's own instruction — "one run is an anecdote, five is data").
5. Run E9 (60-min game day) via `POST /schedule` with an interval, let it run for an hour under load, record overall availability.
6. Take Grafana screenshots of every experiment with the annotation windows visible (this is a doc §17 deliverables checklist item).

### 3.3 Chaos Mesh comparison (optional, doc §4/§13.4 item 5)
Doc suggests installing Chaos Mesh as a baseline comparison for 1-2 experiments. Not started. If time is short, this is the first thing to cut (doc's own cut-list logic applies).

### 3.4 Cost analysis with real numbers
Doc §14 has placeholder tables (`$X`, `$Y`, `$Z`). Once deployed for even a short window, pull real numbers from AWS Cost Explorer and fill these in. This is explicitly called out in doc's closing note as one of the things NOT to cut.

### 3.5 CI/CD pipeline has never actually run
`.github/workflows/ci.yml` and `deploy.yml` are written but this repo has never been pushed to GitHub before now, so neither has ever executed. Once pushed (§4 below), a push to `main` will trigger `ci.yml` automatically — check it actually goes green; the per-service `make test` targets referenced don't fully exist yet (services have no real test suites, only manual verification was done — see §3.6).

### 3.6 No automated test suites exist
Everything verified in §2 was manual curl-based verification during the testing session, not committed test code. There are no `pytest`/`go test`/`jest` files anywhere in `services/`. If the report needs to claim automated test coverage, this needs to be written from scratch — the manual verification steps in the session that produced this handoff are a good starting point for what to automate (see the ride-flow sequence in §2.1, the degradation-path toggles in §2.6 item 3-4 discovery, etc.)

### 3.7 The research paper itself does not exist yet
See §5 for a suggested structure. Nothing has been written.

---

## 4. Getting this pushed and handed off

This repo is being pushed to GitHub as a **public** repository as part of this handoff. Whoever continues should:

```bash
git clone <the repo URL you were given>
cd RideFlow-Chaos-Platform
docker compose up -d --build     # full local stack, ~3 min first time
```
Then read `README.md` for the quickstart, and `docs/api/contracts.md` before changing any service.

If GitHub Actions CI isn't green after the initial push, that's expected per §3.5 — it's the first real run.

---

## 5. Suggested research paper structure

Map directly onto the original doc's sections — it was written with exactly this report in mind:

1. **Abstract / Problem statement** — doc §1-2, verbatim framing is good: this is an empirical resilience *and* security report, not a deployment exercise.
2. **Related work** — doc §4's table (Chaos Monkey, Chaos Mesh, LitmusChaos, Gremlin) is a ready-made literature survey. Add a security-tooling comparison row (OWASP ZAP, Burp Suite) for the new security-injector contribution — the honest positioning per `docs/security/baseline-findings.md`'s "Honest scope note" is: a targeted tool for this app's specific attack surface, not a general DAST replacement.
3. **System architecture** — doc §5, plus the security-injector's architecture (mirrors the chaos-injector's design deliberately — same lifecycle shape, same safety-control philosophy — worth diagramming as a sibling system).
4. **Methodology** — the hypothesis-first chaos methodology (doc §8.1) + the attack-and-verdict methodology (each security attack produces a pass/fail finding with evidence, `security-injector/app/models.py::Finding`).
5. **Results**:
   - MTTD/MTTR table from §3.2's now-completed experiment matrix, with the MTTR-by-layer analysis (doc §13.4 item 1 — expect ~2 orders of magnitude between circuit-breaking and DNS failover; this is the single most citable finding if it holds).
   - Security posture score and findings table (already have a real baseline in `docs/security/baseline-findings.md`; re-run after deployment for a real vs. local comparison).
   - **The bug-discovery narrative from §2.6 is genuinely good result material**: "N real defects were found by running these tools against the system under test, M of which were fixed during development" — this is a legitimate empirical claim about tool effectiveness, not just a feature list.
6. **Cost analysis** — doc §14, filled with real numbers per §3.4.
7. **Limitations** — doc §15's table is already comprehensive; add the security-injector's own honest scope limits from `docs/security/baseline-findings.md`.
8. **Conclusion**.

---

## 6. Known gotchas for whoever continues (save yourself the debugging time)

- **Docker Desktop on Windows can idle out** and looks exactly like a crash (all containers "Exited", `docker info` fails). Not a bug in this project — just restart Docker Desktop.
- **k6 is not installed** in the dev environment this was built in. Either install it, or run via `docker run --network rideflow -v $(pwd)/loadtest:/scripts grafana/k6 run /scripts/steady-state.js` (adjust `BASE_URL` for in-network hostnames if doing this).
- **Windows Git Bash path-mangling**: commands like `docker exec <container> cat /tmp/foo` get their Unix-looking path silently rewritten to a Windows path by MSYS. Prefix with `MSYS_NO_PATHCONV=1` or `export MSYS_NO_PATHCONV=1` first if you hit mysterious "file not found" errors that look like they shouldn't happen.
- **The default JWT secret is intentionally insecure** (`dev-secret-not-for-prod` in `services/user-service/src/index.js`) — this is deliberate, so the `jwt-tampering` security attack has something real to find. **Must be overridden via the `JWT_SECRET` env var before any real deployment** — the security-injector will flag this as CRITICAL if you forget, which is the point.
- **`GF_ANALYTICS_CHECK_FOR_UPDATES=false` etc. in docker-compose.yml** are load-bearing, not optional — without them Grafana can take 10+ minutes to start on a network-restricted machine (see bug #2 in §2.6).
- Chaos/security run history is stored in named Docker volumes (`chaos-state`, `security-state`) — `docker compose down -v` wipes it, plain `docker compose down` doesn't.
