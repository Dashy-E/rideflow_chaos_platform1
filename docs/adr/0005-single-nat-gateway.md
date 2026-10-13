# ADR-0005: Single NAT Gateway per region

**Status:** Accepted

## Context
A NAT Gateway per AZ (3 per region) is the resilient default but costs
~3x more than one.

## Decision
One NAT Gateway per region, placed in AZ-a.

## Consequences
- (+) Saves ~$66/month across both regions.
- (−) AZ-a becomes a single point of failure for private-subnet egress in
  that region — if AZ-a is lost, nodes in AZ-b/AZ-c lose internet egress
  until AWS reroutes or we intervene.
- (+ as a side effect) This makes AZ-a a more interesting, honest chaos
  target for the F5 (AZ blackhole) experiment — draining AZ-a exercises both
  the topology-spread/PDB recovery path *and* the NAT single-point-of-failure
  simultaneously. Documented as a deliberate cost tradeoff, not an oversight
  (doc §15 risk #6).
