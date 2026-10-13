.PHONY: up down kind-up kind-down load-test load-test-spike chaos-demo security-demo logs ps

# Base URL the chaos-injector / k6 talk to. Override: make chaos-demo CHAOS_URL=...
CHAOS_URL ?= http://localhost:9000
SECURITY_URL ?= http://localhost:9001
BASE_URL ?= http://localhost:8080
KIND_CLUSTER ?= rideflow

## up: bring up the full local dev stack (5 services + chaos-injector + redis + prometheus + grafana + dashboard)
up:
	docker compose up --build -d
	@echo "dashboard         -> http://localhost:5173  (Mission Control: overview/chaos/security/logs)"
	@echo "api-gateway       -> http://localhost:8080"
	@echo "chaos-injector    -> http://localhost:9000"
	@echo "security-injector -> http://localhost:9001"
	@echo "prometheus        -> http://localhost:9090"
	@echo "grafana           -> http://localhost:3001 (admin/admin)"

## down: tear the stack down. This is also the "cost discipline" habit per doc §14.3 —
## run it at the end of every session so nothing keeps billing/consuming resources.
down:
	docker compose down --remove-orphans

## kind-up: create the local 3-node kind cluster and bootstrap platform add-ons
kind-up:
	kind create cluster --name $(KIND_CLUSTER) --config deploy/kind-config.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/metrics-server/latest/download/components.yaml
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	helm repo update
	helm install kps prometheus-community/kube-prometheus-stack -n observability --create-namespace

## kind-down: destroy the local kind cluster (cost/resource discipline)
kind-down:
	kind delete cluster --name $(KIND_CLUSTER)

## load-test: run the k6 steady-state load test against the local stack
load-test:
	k6 run -e BASE_URL=$(BASE_URL) loadtest/steady-state.js

## load-test-spike: run the k6 spike test (50 -> 500 RPS ramp) to demo HPA scale-out
load-test-spike:
	k6 run -e BASE_URL=$(BASE_URL) loadtest/spike-test.js

## chaos-demo: trigger a pod-kill chaos experiment via the chaos-injector control API
chaos-demo:
	curl -sf -X POST $(CHAOS_URL)/experiments/pod-kill-ride-service/run | tee /dev/stderr

## security-demo: run the JWT-tampering attack via the security-injector control API
security-demo:
	curl -sf -X POST $(SECURITY_URL)/attacks/jwt-tampering-user-service/run | tee /dev/stderr

## logs: tail logs for the whole compose stack
logs:
	docker compose logs -f --tail=200

## ps: show status of the compose stack
ps:
	docker compose ps
