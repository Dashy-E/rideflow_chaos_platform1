# Deploying the dashboard to Vercel

Vercel hosts static sites and short-lived serverless functions. It cannot run
RideFlow's backend: the five services, Redis, Prometheus, Grafana and the two
injectors are long-running containers, and the chaos injector needs the Docker
socket. So the deployment is split:

| Part | Where it runs |
|---|---|
| Mission Control dashboard (`frontend/dist`) | **Vercel** |
| `/api/chaos/*`, `/api/security/*` proxy (`api/proxy.js`) | **Vercel** (serverless function) |
| Everything else (`docker-compose.yml`) | A server you control, e.g. the free-tier EC2 box in `infra/free-tier-ec2/` |

The browser only talks to Vercel over HTTPS; the proxy function forwards
control-API calls to the backend server-side. That avoids mixed-content
blocking (an HTTPS page can't call an `http://` backend) and CORS.

## 1. Run the backend somewhere reachable

Follow `infra/free-tier-ec2/README.md`. Vercel's outbound IPs aren't fixed, so
the chaos/security ports must be reachable from the internet:

```bash
cd infra/free-tier-ec2
terraform apply -var="instance_type=t3.medium"   # allowed_app_cidr defaults to 0.0.0.0/0
```

Note the `public_ip` output.

## 2. Import the repo into Vercel

1. vercel.com → **Add New… → Project** → import this GitHub repo.
2. Leave **Framework Preset** as *Other* and the root directory as `./`.
   `vercel.json` already sets the output directory (`frontend/dist`), the
   function, and the `/api/*` rewrites. There is no build step.
3. Under **Environment Variables** add:

   | Name | Value |
   |---|---|
   | `RIDEFLOW_BACKEND_URL` | `http://<public_ip>` (no port) |
   | `DASHBOARD_PASSWORD` | a password. Strongly recommended: without it anyone with the URL can run chaos experiments |

   Optional: `RIDEFLOW_CHAOS_URL` / `RIDEFLOW_SECURITY_URL` to override the
   default `<backend>:9000` / `<backend>:9001`.
4. **Deploy.** Every push to `main` redeploys automatically; other branches
   get preview URLs.

If the backend IP changes (e.g. after `terraform destroy` + `apply`), update
`RIDEFLOW_BACKEND_URL` and redeploy (Deployments → ⋯ → Redeploy).

## How it behaves

- Opening the Vercel URL prompts for the password (any username) when
  `DASHBOARD_PASSWORD` is set.
- **Run experiment** returns after at most 20s with "started"; the run keeps
  going on the backend and the dashboard's 2s polling shows its progress.
  Chaos experiments last minutes, far past a serverless function's timeout.
- The Grafana/Prometheus links in the sidebar point straight at the backend
  (`http://<public_ip>:3001` / `:9090`).
- The same `index.html` still works unchanged from the compose stack
  (`http://localhost:5173`, or `http://<public_ip>:5173` on EC2): on port 5173
  it calls the injectors directly instead of going through `/api`.

## Security caveat

`DASHBOARD_PASSWORD` protects the Vercel proxy only. The backend's own ports
(9000/9001 and the rest) are still open on the EC2 box itself, and the chaos
injector has the Docker socket mounted. Treat the box as a short-lived demo
environment and `terraform destroy` it when you're done.
