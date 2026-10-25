# 0002. PostgreSQL as a StatefulSet first, RDS later

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
The task tracker needs PostgreSQL. In production on AWS the usual choice is Amazon RDS, a managed service with backups, Multi-AZ failover and patching. This platform deliberately runs the database in-cluster first, to see the operational trade-offs of stateful workloads on Kubernetes, and it is destroyed after every session.

## Decision
- **Phase 1:** run PostgreSQL in-cluster as a **StatefulSet** with a headless Service and a `volumeClaimTemplate` backed by **EBS gp3** (EBS CSI driver). Credentials come from Secrets Manager through External Secrets ([ADR 0004](0004-external-secrets-operator.md)).
- **Phase 2 (roadmap M11):** migrate to **Amazon RDS for PostgreSQL**. The api reads its connection settings from config and a Secret, so the switch needs no code change.

## Consequences
- The platform covers StatefulSets, stable network identity, PVCs, storage classes and the AZ affinity of EBS volumes.
- This costs less than RDS and is created and destroyed together with the cluster.
- There are no managed backups, no point-in-time recovery and no HA (single replica). **Data is lost when the cluster is destroyed.** That's acceptable for lab data only.
- An EBS volume is tied to one AZ, so the Postgres pod can only be scheduled in that AZ.

## Alternatives considered
- **RDS from day one:** the production choice, but it skips the in-cluster stateful workload and adds about $15+/month.
- **Bitnami / CloudNativePG operator:** more features (replication, backups). We start with a hand-written chart to keep every moving part visible, and may revisit later.
- **Aurora Serverless v2:** more than this app needs, and its minimum capacity still costs money.
