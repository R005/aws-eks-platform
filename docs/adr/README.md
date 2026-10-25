# Architecture Decision Records

An ADR is a short document that records one significant decision: its context, what we decided, and the consequences. See [ADR 0001](0001-record-architecture-decisions.md).

## Adding an ADR

1. Copy the template below into `NNNN-short-kebab-title.md`, using the next free number.
2. Set the Status to `Proposed`, then change it to `Accepted` once the change is merged.
3. Never rewrite an accepted ADR. To change a decision, write a new ADR and mark the old one `Superseded by NNNN`.
4. Add the new ADR to the index below.

## Template

```markdown
# NNNN. Title

- **Status:** Proposed | Accepted | Superseded by NNNN
- **Date:** YYYY-MM-DD

## Context
What problem or force makes this decision necessary?

## Decision
What we will do.

## Consequences
What becomes easier, what becomes harder, and any follow-ups.

## Alternatives considered
- Option: why we did not choose it.
```

## Index

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
| [0011](0011-gateway-api-for-ingress.md) | Gateway API via AWS Load Balancer Controller | Accepted |
| [0012](0012-api-stack-and-migrations.md) | api stack: uv, SQLAlchemy + psycopg, Alembic as a separate step, distroless runtime | Accepted |
