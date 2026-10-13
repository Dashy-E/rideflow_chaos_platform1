# ADR-0001: Amazon EKS over self-managed kubeadm

**Status:** Accepted

## Context
We need a Kubernetes control plane in two AWS regions within a 12-week, 5-person
project timeline.

## Decision
Use Amazon EKS (managed control plane) rather than self-managed kubeadm on EC2.

## Consequences
- (+) No time spent on control-plane HA, etcd backups, or version skew — that
  effort goes into the chaos injector and experiments instead, which is where
  the project's actual grade-bearing content lives.
- (+) Native IRSA/OIDC integration simplifies least-privilege pod identity.
- (−) ~$0.10/hr per cluster control plane, unavoidable even when idle — a
  direct input to the cost-optimised operating model in doc §14.2.
- (−) Slightly less visibility into control-plane internals for the report's
  CO5 orchestration section than self-managing would give; mitigated by
  discussing what EKS manages vs. what still requires our configuration
  (node groups, addons, IRSA).
