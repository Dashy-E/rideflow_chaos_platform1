# RideFlow — Service Contracts (authoritative for all builders/agents)

Ports, env vars, health semantics and endpoints below are fixed — do not diverge, other modules (Helm probes, Prometheus scrape configs, k6 scripts, chaos injector selectors) depend on these exact values.

## Ports & container names (docker-compose / k8s Service names)
| Service | Container/Service name | Port | Language |
|---|---|---|---|
| api-gateway | `api-gateway` | 8080 | Go |
| user-service | `user-service` | 8081 | Node.js/Express |
| ride-service | `ride-service` | 8082 | Python/FastAPI |
| driver-service | `driver-service` | 8083 | Go |
| pricing-service | `pricing-service` | 8084 | Python/FastAPI |
| chaos-injector | `chaos-injector` | 9000 | Python/FastAPI |
| security-injector | `security-injector` | 9001 | Python/FastAPI |
| redis | `redis` | 6379 | — |
| prometheus | `prometheus` | 9090 | — |
| grafana | `grafana` | 3000 | — |
| dashboard (frontend) | `dashboard` | 5173 | static |

All app services expose: `GET /healthz`, `GET /readyz`, `GET /metrics` (Prometheus exposition format).
`api-gateway` additionally exposes `GET /healthz/region` (used by chaos F6 / Route 53 in the AWS path).

## Environment variables (every service)
- `PORT` — override default port
- `LOG_LEVEL` — default `info`
- `REGION` — `local` in dev, `ap-south-1`/`ap-southeast-1` in AWS
- `REDIS_URL` — `redis://redis:6379` (driver-service)
- `PROMETHEUS_URL` — `http://prometheus:9090` (chaos-injector)
- `CHAOS_FAULT_HEADER` — `x-chaos-fault` — app-level fault injection: services read this header (or `CHAOS_INJECT` env for standing faults) and simulate latency/error per experiment, per §Fault F3/F8 "application-level" option in the spec.

## Public API (via api-gateway, prefix `/v1`)
- `POST /v1/rides` → proxies to ride-service `/internal/rides`
- `GET /v1/rides/{id}`
- `GET /v1/drivers/nearby?lat&lng&radius`
- `GET /v1/users/me`
- `POST /v1/auth/login`
- `POST /v1/users`

## Internal API
- user-service: `GET /internal/users/{id}/validate`
- ride-service: `POST /internal/rides`, `GET/PATCH /internal/rides/{id}`, `POST /internal/rides/{id}/cancel`
- driver-service: `POST /internal/match`, `PUT /internal/drivers/{id}/location`
- pricing-service: `POST /internal/quote`

## Chaos injector control API (port 9000)
`GET /experiments`, `POST /experiments/{id}/run`, `GET /runs`, `GET /runs/{id}`, `POST/DELETE /schedule`, `POST /abort`, `GET /metrics`, `GET /metrics/summary` (RPS/error-rate/p99/rides-per-min for the dashboard), `GET /status` (dashboard summary).

## Security injector control API (port 9001)
`GET /attacks`, `POST /attacks/{id}/run`, `GET /runs`, `GET /runs/{id}`, `POST /abort`, `POST /kill-switch`, `GET /posture` (rollup score), `GET /status`, `GET /metrics`.
Attack definitions live in `attacks/*.yaml` (mirrors `experiments/*.yaml`'s shape). Every attack module in `security-injector/app/attacks.py` hardcodes its own targets to RideFlow's own `SERVICE_URLS` — there is no parameter that lets a caller point it at anything else.

## Metrics every service must emit
```
http_requests_total{service,method,route,code}
http_request_duration_seconds_bucket{service,method,route,le}
http_requests_in_flight{service}
dependency_requests_total{service,dependency,outcome}
circuit_breaker_state{service,dependency}
```
