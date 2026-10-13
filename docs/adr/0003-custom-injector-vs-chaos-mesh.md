# ADR-0003: Custom chaos injector over Chaos Mesh / LitmusChaos

**Status:** Accepted

## Context
CNCF tools (Chaos Mesh, LitmusChaos) already implement CRD-driven fault
injection on Kubernetes well. The project needs to demonstrate original
engineering, not just operate an existing tool.

## Decision
Build a custom FastAPI + `kubernetes` client injector (`chaos-injector/`) that
owns both fault injection *and* recovery measurement, and use Chaos Mesh only
as a capability-comparison baseline for one or two experiments.

## Consequences
- (+) Injection and measurement are coupled: every run automatically emits an
  annotated recovery timeline and computes MTTD/MTTR against a declared
  steady-state hypothesis (`chaos-injector/app/engine.py`). Chaos Mesh injects
  faults well but treats measurement as an external concern — this is the
  actual gap the project addresses (doc §4).
- (+) Full control over the safety model: kill switch, concurrency limit of 1,
  namespace denylist, auto-revert on crash via a persisted state file — all
  visible, auditable code rather than a third-party CRD's behavior.
- (−) More code to write and defend in a viva than installing a Helm chart.
- (−) Less battle-tested than Chaos Mesh for exotic fault types; scope was
  deliberately kept to the 8-fault catalogue in doc §8.2.
