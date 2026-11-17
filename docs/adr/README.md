# Architecture Decision Records

Each ADR records one significant decision ([ADR 0001](0001-record-architecture-decisions.md)). To add one, copy the template into `NNNN-short-kebab-title.md` with the next free number, start it as `Proposed`, mark it `Accepted` once merged, and add it to the index. To change a decision, write a new ADR and mark the old one `Superseded by NNNN`.

```markdown
# NNNN. Title

Status: Proposed, YYYY-MM-DD

## Context

## Decision

## Consequences
```

| No. | Title | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-postgres-statefulset-first-rds-later.md) | PostgreSQL as a StatefulSet first, RDS later | Accepted |
| [0003](0003-s3-native-state-locking.md) | S3 native state locking for Terraform | Accepted |
| [0004](0004-external-secrets-operator.md) | External Secrets Operator for secrets sync | Accepted |
| [0005](0005-irsa-for-pod-aws-access.md) | IRSA for pod AWS access | Accepted |
| [0006](0006-amd64-nodes-multi-arch-images.md) | x86 (amd64) worker nodes with multi-arch image builds | Accepted |
| [0007](0007-single-nat-gateway-in-lab.md) | Single NAT Gateway in the lab | Accepted |
| [0008](0008-gitlab-shared-runners.md) | GitLab.com shared runners | Accepted |
| [0009](0009-trunk-based-git-workflow.md) | Trunk-based Git workflow | Accepted |
| [0010](0010-dns-delegated-lab-subdomain.md) | DNS: delegate `lab.<domain>` to Route 53 | Accepted |
| [0011](0011-gateway-api-for-ingress.md) | Gateway API via AWS Load Balancer Controller | Superseded by 0014 |
| [0012](0012-api-stack-and-migrations.md) | api stack: uv, SQLAlchemy + psycopg, Alembic as a separate step, distroless runtime | Accepted |
| [0013](0013-eks-access-entries-only.md) | Cluster access via EKS access entries only (API mode) | Accepted |
| [0014](0014-ingress-via-aws-load-balancer-controller.md) | Ingress via AWS Load Balancer Controller | Accepted |
