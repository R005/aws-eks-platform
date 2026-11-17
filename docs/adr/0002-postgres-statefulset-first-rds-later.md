# 0002. PostgreSQL as a StatefulSet first, RDS later

Status: Accepted, 2026-10-25

## Context

The task tracker needs PostgreSQL. On AWS the usual production choice is RDS, but this platform is destroyed after every session and is meant to show the trade-offs of stateful workloads on Kubernetes.

## Decision

Run PostgreSQL in the cluster first, as a StatefulSet with a headless Service and an EBS `gp3` volume claim, with credentials from Secrets Manager through External Secrets ([ADR 0004](0004-external-secrets-operator.md)). Move to Amazon RDS for PostgreSQL at roadmap M11. The api reads its connection settings from config, so the switch needs no code change.

## Consequences

It is cheaper than RDS and comes and goes with the cluster. There are no managed backups, no point-in-time recovery and no HA, and data is lost when the cluster is destroyed, which is acceptable for lab data only. An EBS volume is tied to one AZ, so the Postgres pod can only run there. An operator such as CloudNativePG may be revisited later.
