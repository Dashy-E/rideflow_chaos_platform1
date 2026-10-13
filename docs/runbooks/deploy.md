# Runbook: Deploy

## Local (docker-compose)
```bash
make up
```

## Kubernetes (kind, local)
```bash
make kind-up
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/metrics-server/latest/download/components.yaml
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kps prometheus-community/kube-prometheus-stack -n observability --create-namespace
helm upgrade --install rideflow deploy/helm/rideflow -n rideflow --create-namespace --wait --timeout 5m
```

## AWS (primary region)
1. Confirm the budget alarm exists (`infra/README.md`) — do this before anything else.
2. `cd infra/global && terraform init && terraform apply`
3. `cd infra/envs/primary && terraform init && terraform apply`
4. `aws eks update-kubeconfig --region ap-south-1 --name rideflow-primary`
5. Install platform components (AWS LB Controller, Cluster Autoscaler, metrics-server,
   kube-prometheus-stack) — see `deploy/k8s/README.md` for the exact `helm install` commands.
6. `helm upgrade --install rideflow deploy/helm/rideflow -n rideflow --create-namespace --wait --timeout 5m`
7. Verify: `kubectl get pods -n rideflow -o wide`, then hit the ALB DNS name's `/healthz`.

## AWS (secondary region)
Same as primary, but `cd infra/envs/secondary`, region `ap-southeast-1`, and
`helm upgrade --install rideflow deploy/helm/rideflow -n rideflow -f deploy/helm/values-secondary.yaml`.

## CI/CD
Push to `main` triggers `.github/workflows/deploy.yml`: build → push to ECR (OIDC,
no static keys) → Trivy scan → deploy-primary → **resilience-gate** (a chaos
smoke test that must pass) → deploy-secondary. A deployment that breaks
self-healing is blocked automatically.
