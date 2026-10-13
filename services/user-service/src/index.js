// user-service — registration, authentication (JWT issue/verify), profile, rider tier.
const express = require("express");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcryptjs");
const { v4: uuidv4 } = require("uuid");
const client = require("prom-client");

const SERVICE = "user-service";
const PORT = process.env.PORT || 8081;
const REGION = process.env.REGION || "local";
const JWT_SECRET = process.env.JWT_SECRET || "dev-secret-not-for-prod";

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequests = new client.Counter({
  name: "http_requests_total",
  help: "requests",
  labelNames: ["service", "method", "route", "code"],
  registers: [register],
});
const httpDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "latency",
  labelNames: ["service", "method", "route"],
  registers: [register],
});
const inflight = new client.Gauge({
  name: "http_requests_in_flight",
  help: "in flight",
  labelNames: ["service"],
  registers: [register],
});

// in-memory store standing in for DynamoDB `users` table in local/dev
const usersById = new Map();
const usersByEmail = new Map();

const app = express();
app.use(express.json());

let runtimeFaultMode = process.env.CHAOS_INJECT || "";
app.patch("/admin/chaos", (req, res) => {
  runtimeFaultMode = (req.query.mode || "").toString();
  res.json({ mode: runtimeFaultMode });
});

app.use((req, res, next) => {
  inflight.inc({ service: SERVICE });
  const start = process.hrtime.bigint();
  const fault = req.header("x-chaos-fault") || runtimeFaultMode;
  const finish = () => {
    inflight.dec({ service: SERVICE });
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    httpDuration.observe({ service: SERVICE, method: req.method, route: req.path }, seconds);
    httpRequests.inc({ service: SERVICE, method: req.method, route: req.path, code: res.statusCode });
  };
  res.on("finish", finish);

  if (fault === "error") {
    res.status(500).send("chaos-injected error");
    return;
  }
  if (fault === "latency") {
    setTimeout(next, Number(process.env.CHAOS_LATENCY_MS || 300));
    return;
  }
  next();
});

app.get("/healthz", (req, res) => res.json({ status: "ok", service: SERVICE, region: REGION }));
app.get("/readyz", (req, res) => res.json({ status: "ready" }));
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.send(await register.metrics());
});

app.post("/v1/users", async (req, res) => {
  const { email, password, tier } = req.body || {};
  if (!email || !password) return res.status(400).json({ error: "email and password required" });
  if (usersByEmail.has(email)) return res.status(409).json({ error: "user already exists" });

  const userId = uuidv4();
  const passwordHash = await bcrypt.hash(password, 12);
  const user = { userId, email, passwordHash, tier: tier || "STANDARD", createdAt: Date.now(), region: REGION };
  usersById.set(userId, user);
  usersByEmail.set(email, user);
  res.status(201).json({ userId, email, tier: user.tier });
});

app.post("/v1/auth/login", async (req, res) => {
  const { email, password } = req.body || {};
  const user = usersByEmail.get(email);
  if (!user || !(await bcrypt.compare(password || "", user.passwordHash))) {
    return res.status(401).json({ error: "invalid credentials" });
  }
  const token = jwt.sign({ sub: user.userId, tier: user.tier }, JWT_SECRET, { expiresIn: "1h" });
  res.json({ token });
});

app.get("/internal/users/:id/validate", (req, res) => {
  const user = usersById.get(req.params.id);
  if (!user) return res.status(404).json({ valid: false });
  res.json({ valid: true, tier: user.tier });
});

app.get("/v1/users/me", (req, res) => {
  const auth = req.header("authorization") || "";
  const token = auth.replace(/^Bearer /, "");
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    const user = usersById.get(payload.sub);
    if (!user) return res.status(404).json({ error: "not found" });
    res.json({ userId: user.userId, email: user.email, tier: user.tier });
  } catch {
    res.status(401).json({ error: "invalid token" });
  }
});

app.listen(PORT, () => console.log(`${SERVICE} listening on ${PORT} (region=${REGION})`));
