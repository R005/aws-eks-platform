# 0013. Cluster access via EKS access entries only (API mode)

- **Status:** Proposed
- **Date:** 2026-10-26

## Context
EKS has to map IAM principals (people, CI, nodes) to Kubernetes identities and permissions. There are two mechanisms:

- **`aws-auth` ConfigMap** (the original): a YAML map in `kube-system` from IAM ARNs to Kubernetes users and groups. It lives *inside* the cluster, so changing it needs working cluster access. One malformed edit can lock every user out, and changes are only visible in the Kubernetes audit log. Role ARNs in it can't include a path, which matters for IAM Identity Center roles (`/aws-reserved/sso.amazonaws.com/`).
- **Access entries** (EKS API): each IAM principal gets an access entry, managed through the EKS API like any other AWS resource, plus either AWS-managed access policies (`AmazonEKSClusterAdminPolicy`, `AmazonEKSAdminPolicy`, `AmazonEKSEditPolicy`, `AmazonEKSViewPolicy`) scoped to the cluster or to namespaces, or Kubernetes groups bound with RBAC. Changes go through IAM-authorised API calls and are logged in CloudTrail.

The cluster's `authentication_mode` chooses which mechanisms are active: `CONFIG_MAP`, `API_AND_CONFIG_MAP` (the default of the Terraform module, mainly for migrations) or `API`.

Humans reach AWS only through IAM Identity Center (SSO). Its role names carry a random suffix that differs per account.

## Decision
- The `eks` stack sets `authentication_mode = "API"`. The `aws-auth` ConfigMap is not used.
- All cluster access is declared in Terraform as access entries:
  - The IAM Identity Center `AdministratorAccess` role gets `AmazonEKSClusterAdminPolicy` at cluster scope. The role is found with an `aws_iam_roles` data source (name pattern and SSO path), and the lookup fails unless exactly one role matches. Its ARN is never written in code.
  - The managed node group's role gets its access entry from EKS automatically.
  - Later principals (CI deploy role, read-only users) get their own entries, with namespace-scoped policies where possible.
- `enable_cluster_creator_admin_permissions = false`: whoever runs `apply` gets no implicit admin. Access comes only from the declared entries.

## Consequences
- Access is reviewed in merge requests, applied by Terraform and audited in CloudTrail. It can be repaired through the EKS API even when no one can reach the Kubernetes API.
- No in-cluster YAML to break, and no ordering problem where Terraform needs cluster access to grant cluster access.
- SSO role ARNs are used as they are, path included.
- Every principal needs an explicit entry. Forgetting one means no access, not too much.
- Moving from `API_AND_CONFIG_MAP` to `API` is one-way. Choosing `API` at creation avoids a migration later.
- Access entry changes are eventually consistent and can take a few seconds to apply.

## Alternatives considered
- **`aws-auth` ConfigMap (`CONFIG_MAP`):** deprecated direction, fragile, managed inside the cluster, and it can't use SSO role paths.
- **`API_AND_CONFIG_MAP`:** only useful while migrating existing clusters. It leaves a second access path that nobody reviews.
- **Cluster creator admin (`enable_cluster_creator_admin_permissions = true`):** convenient, but access then depends on who ran `apply`. For the SSO role it would also create a second access entry for the same principal, and the apply would fail.
