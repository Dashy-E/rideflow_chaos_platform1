# ADR-0006: Polyglot service implementation (Go, Node.js, Python)

**Status:** Accepted, with an explicit fallback

## Context
Five people, five services, three languages (Go: api-gateway, driver-service;
Node.js: user-service; Python/FastAPI: ride-service, pricing-service).

## Decision
Keep the stack polyglot deliberately, per the original spec, because it
produces direct evidence for CO2 (containerization abstracts the runtime —
demonstrated by comparing multi-stage image sizes across languages) and
avoids concentrating all application code with one or two people.

## Consequences
- (+) Distroless Go binaries land around 14MB vs. ~150-190MB for the Python/
  Node services — a concrete, measured CO2 data point for the report.
- (+) Forces the OpenAPI contract (`docs/api/contracts.md`) to be the actual
  source of truth between services, since no shared in-process types exist
  across language boundaries — this is a feature, not friction.
- (−) Higher integration cost with only 12 weeks and 5 people (doc §15 risk
  #9). **Fallback, per doc's own cut list**: if integration pain shows up by
  week 3, standardize on Go + Python only and say so explicitly in the report
  rather than pretending polyglot was maintained throughout.
