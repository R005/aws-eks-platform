# 0004. External Secrets Operator for secrets sync

Status: Accepted, 2026-10-25

## Context

Apps need secrets such as the database password. These must never be in Git, Helm values or CI variables rendered into manifests. Secrets Manager is the source of truth, and pods consume ordinary Kubernetes Secrets.

## Decision

Install External Secrets Operator with Helm in the `addons` stack. A `ClusterSecretStore` points at Secrets Manager and authenticates with IRSA ([ADR 0005](0005-irsa-for-pod-aws-access.md)), using a role that can only read secrets named `eks-platform/dev/*`. Each app chart ships an `ExternalSecret` with a `refreshInterval`, so rotations sync automatically. Terraform may create the secret resource, but the value is never committed.

## Consequences

No secret values are in the repo, and rotation happens in one place. Kubernetes Secrets are only base64-encoded, so etcd encryption and RBAC still matter. The operator is another controller to run; if it is down, existing Secrets keep working but changes stop syncing. The Secrets Store CSI driver was not chosen because it handles env vars awkwardly and needs a mount on every pod.
