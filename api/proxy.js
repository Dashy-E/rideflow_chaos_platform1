// Vercel serverless proxy for the Mission Control dashboard.
//
// Vercel can host the dashboard (frontend/dist) but not the backend itself:
// the services, Redis, Prometheus and the chaos injector are long-running
// containers (the injector also needs the docker socket). So the backend runs
// elsewhere (e.g. infra/free-tier-ec2) and this function forwards the
// dashboard's control-API calls to it server-side. vercel.json rewrites
//   /api/chaos/<path>    -> /api/proxy?target=chaos&path=<path>
//   /api/security/<path> -> /api/proxy?target=security&path=<path>
//   /api/config          -> /api/proxy?target=config
//
// Environment variables (Vercel project settings):
//   RIDEFLOW_BACKEND_URL   required, e.g. http://13.234.10.20 (the EC2 public IP)
//   RIDEFLOW_CHAOS_URL     optional override, default <backend>:9000
//   RIDEFLOW_SECURITY_URL  optional override, default <backend>:9001
//   DASHBOARD_PASSWORD     optional; if set, /api/* requires HTTP Basic auth
//                          with this password (any username)

const crypto = require("crypto");

// Starting an experiment/attack holds the request open until the run ends
// (minutes for chaos experiments), far past a serverless timeout. The backend
// keeps running after the caller disconnects, so answer 202 after this long
// and let the dashboard's 2s status polling show progress.
const RUN_WAIT_MS = 20000;
const REQUEST_TIMEOUT_MS = 15000;

function backendOrigin(port) {
  const base = process.env.RIDEFLOW_BACKEND_URL;
  if (!base) return null;
  const u = new URL(base);
  u.port = String(port);
  return u.origin;
}

const TARGETS = {
  chaos: () => process.env.RIDEFLOW_CHAOS_URL || backendOrigin(9000),
  security: () => process.env.RIDEFLOW_SECURITY_URL || backendOrigin(9001),
};

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "no-store");
  res.end(typeof body === "string" ? body : JSON.stringify(body));
}

function authorized(req) {
  const password = process.env.DASHBOARD_PASSWORD;
  if (!password) return true;
  const header = req.headers.authorization || "";
  if (!header.startsWith("Basic ")) return false;
  const decoded = Buffer.from(header.slice(6), "base64").toString();
  const given = decoded.slice(decoded.indexOf(":") + 1);
  const a = crypto.createHash("sha256").update(given).digest();
  const b = crypto.createHash("sha256").update(password).digest();
  return crypto.timingSafeEqual(a, b);
}

module.exports = async function handler(req, res) {
  if (!authorized(req)) {
    res.setHeader("WWW-Authenticate", 'Basic realm="RideFlow Mission Control"');
    return send(res, 401, { detail: "authentication required" });
  }

  const url = new URL(req.url, "http://localhost");
  const target = url.searchParams.get("target");

  if (target === "config") {
    return send(res, 200, {
      grafanaUrl: backendOrigin(3001),
      prometheusUrl: backendOrigin(9090),
    });
  }

  const upstream = TARGETS[target] && TARGETS[target]();
  if (!upstream) {
    return send(res, target in TARGETS ? 503 : 404, {
      detail: target in TARGETS
        ? "RIDEFLOW_BACKEND_URL is not set in the Vercel project's environment variables"
        : `unknown target ${target}`,
    });
  }

  const path = url.searchParams.get("path") || "";
  if (!/^[A-Za-z0-9._\/-]*$/.test(path) || path.split("/").includes("..")) {
    return send(res, 400, { detail: "invalid path" });
  }
  const query = new URLSearchParams(url.searchParams);
  query.delete("target");
  query.delete("path");
  const qs = query.toString();
  const dest = `${upstream}/${path}${qs ? "?" + qs : ""}`;

  const init = { method: req.method, headers: {} };
  if (req.method !== "GET" && req.method !== "HEAD" && req.body !== undefined) {
    init.body = typeof req.body === "string" ? req.body : JSON.stringify(req.body);
    init.headers["Content-Type"] = req.headers["content-type"] || "application/json";
  }

  const isRun = req.method === "POST" && /\/run$/.test(path);
  const controller = new AbortController();
  init.signal = controller.signal;
  const upstreamCall = fetch(dest, init).then(async (r) => ({ status: r.status, text: await r.text() }));

  let timer;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve(null), isRun ? RUN_WAIT_MS : REQUEST_TIMEOUT_MS);
  });

  try {
    const result = await Promise.race([upstreamCall, timeout]);
    if (result) return send(res, result.status, result.text);
    if (isRun) {
      return send(res, 202, { started: true, detail: "run started; follow it on the dashboard" });
    }
    controller.abort();
    return send(res, 504, { detail: `backend did not answer within ${REQUEST_TIMEOUT_MS / 1000}s` });
  } catch (e) {
    return send(res, 502, { detail: `backend unreachable at ${upstream}: ${e.message}` });
  } finally {
    clearTimeout(timer);
  }
};
