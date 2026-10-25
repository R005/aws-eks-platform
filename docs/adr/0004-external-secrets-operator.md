# 0004. External Secrets Operator for secrets sync

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
The apps need secrets, such as the database password. These must never be stored in Git, Helm values or CI variables that get rendered into manifests. The source of truth is **AWS Secrets Manager**. Pods consume ordinary Kubernetes Secrets (env vars or mounted files).

## Decision
Install **External Secrets Operator (ESO)** using Helm in the `addons` stack.

- A `ClusterSecretStore` points at AWS Secrets Manager in the cluster's region and authenticates with **IRSA** ([ADR 0005](0005-irsa-for-pod-aws-access.md)), using a role that can read only `eks-platform/*` secrets.
- Each app chart ships an `ExternalSecret` that maps Secrets Manager keys to a Kubernetes Secret, with a `refreshInterval` so rotations sync automatically.
- Secrets are created in Secrets Manager outside Git. Terraform can create the secret *resource*, but the value is never committed.

## Consequences
- No secret values in the repo. Rotation happens in one place.
- Kubernetes Secrets are only base64-encoded, so etcd encryption (EKS envelope encryption with KMS) and RBAC still matter.
- ESO is another controller to run and upgrade. If it is down, existing Secrets keep working but changes stop syncing.

## Alternatives considered
- **Secrets Store CSI Driver + AWS provider:** mounts secrets as files without creating Kubernetes Secrets by default. Env-var use is clumsier, and it needs a mount on every pod.
- **Sealed Secrets / SOPS:** encrypted secrets *in Git*. That works, but the source of truth stays in the repo instead of Secrets Manager.
- **Reading Secrets Manager from app code:** couples the app to AWS and adds SDK calls and IAM to every service.
