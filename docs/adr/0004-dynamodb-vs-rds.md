# ADR-0004: DynamoDB Global Tables over RDS

**Status:** Accepted

## Context
`users` and `rides` need a persistent store reachable from two regions with
minimal operational overhead.

## Decision
DynamoDB Global Tables (on-demand billing) rather than RDS (even with a
cross-region read replica).

## Consequences
- (+) Global Tables replication is native and requires no manual failover
  orchestration — RDS cross-region replicas need a manual (or Route 53
  health-check-driven) promotion step, adding another moving part to debug
  under time pressure.
- (+) On-demand billing keeps idle cost near zero, consistent with the
  cost-optimised operating model.
- (−) Eventually consistent, last-writer-wins across regions — a rider could
  theoretically see stale ride state immediately after failover (doc §15
  risk #4). Documented explicitly rather than claimed away; the demo scope
  accepts eventual consistency.
- (−) Query flexibility is lower than SQL — acceptable given the access
  patterns (`GET by rideId`, `GET by userId` via GSI) are simple and known
  upfront.
