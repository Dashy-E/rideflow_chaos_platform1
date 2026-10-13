"""Attack definition schema — deliberately mirrors the chaos experiment
schema in chaos-injector/app/models.py so the two engines feel like one
system from the dashboard's point of view."""
from typing import Literal

from pydantic import BaseModel

AttackType = Literal[
    "auth_bruteforce", "rate_limit_pressure", "jwt_tampering",
    "injection_fuzz", "idor_probe", "internal_endpoint_recon",
]


class AttackDefinition(BaseModel):
    id: str
    description: str
    type: AttackType
    target_service: str  # must be one of our own services — enforced in engine
    severity_if_vulnerable: Literal["low", "medium", "high", "critical"] = "medium"
    params: dict = {}


class Finding(BaseModel):
    check: str
    passed: bool  # True = defended correctly, False = vulnerability found
    detail: str
    evidence: str | None = None


class AttackRun(BaseModel):
    runId: str
    attackId: str
    status: Literal["running", "completed", "aborted", "error"] = "running"
    startedAt: float | None = None
    finishedAt: float | None = None
    findings: list[Finding] = []
    verdict: Literal["defended", "vulnerable", "partial", "unknown"] = "unknown"
    log: list[str] = []
