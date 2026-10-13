# ADR-0002: Warm standby over active-active multi-region

**Status:** Accepted

## Context
Two regions are required to demonstrate Route 53 failover (CO3) and Chaos Kong
-style region-failure experiments (F6). Active-active writes would need a
conflict-resolution strategy on top of DynamoDB Global Tables' last-writer-wins
semantics — a project on its own (doc §15.1 non-goal).

## Decision
Secondary region runs the full stack at minimum replica count (1 vs. 3) and
scales up only once it starts receiving failover traffic — "Pilot Light+".

## Consequences
- (+) Secondary region costs far less to run continuously (~$150/mo vs. full
  active-active cost).
- (+) Sidesteps write-conflict resolution entirely — reads are eventually
  consistent, writes always land on whichever region is currently "primary"
  in the failover topology.
- (−) A latent breakage in the secondary can go unnoticed until a real
  failover. Mitigation: periodic synthetic canary requests against the
  secondary ALB directly (doc §15 risk #3), not covered by CI/CD.
- (−) DNS failover floor of 60–95s (health-check interval + TTL) is a hard
  property of this pattern, not something to engineer around. Report it as a
  finding, not a defect — see doc §7.3.
