# 0013. Cluster access via EKS access entries only (API mode)

Status: Accepted, 2026-10-26

## Context

EKS maps IAM principals to Kubernetes permissions either through the `aws-auth` ConfigMap or through access entries. The ConfigMap lives inside the cluster, one bad edit can lock everyone out, and it cannot hold role ARNs with a path, which IAM Identity Center roles have. Access entries are managed through the EKS API, use AWS managed access policies or RBAC groups, and are logged in CloudTrail. People reach AWS only through IAM Identity Center, whose role names carry a random per-account suffix.

## Decision

The `eks` stack sets `authentication_mode = "API"`, so the ConfigMap is not used. All access is declared in Terraform as access entries. The Identity Center `AdministratorAccess` role gets `AmazonEKSClusterAdminPolicy`; it is found by name pattern, and the lookup fails unless exactly one role matches. The node role gets its entry from EKS. Later principals, such as a CI deploy role, get their own entries, namespace-scoped where possible. `enable_cluster_creator_admin_permissions` is false.

## Consequences

Access is reviewed in merge requests, audited in CloudTrail and repairable through the EKS API even when nobody can reach the cluster. Every principal needs an explicit entry, so a missing one means no access rather than too much. Moving to `API` is one-way, so choosing it at creation avoids a migration. Creator admin would also have created a duplicate entry for the SSO role and failed the apply.
