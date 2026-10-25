# 0005. IRSA for pod AWS access

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
Several pods call AWS APIs: the AWS Load Balancer Controller, ExternalDNS, External Secrets, and the EBS CSI driver. Giving the node's instance role all of these permissions would let *every* pod on the node use them. We want per-workload, least-privilege, short-lived credentials.

## Decision
Use **IAM Roles for Service Accounts (IRSA)**:

- The `eks` stack creates an IAM OIDC identity provider for the cluster's OIDC issuer.
- Each workload gets its own IAM role. The trust policy allows `sts:AssumeRoleWithWebIdentity` only for `system:serviceaccount:<namespace>:<serviceaccount>`, and checks the `aud` claim (`sts.amazonaws.com`).
- The ServiceAccount is annotated with `eks.amazonaws.com/role-arn`. The EKS pod identity webhook injects a projected token, and the AWS SDK exchanges it for temporary credentials.

**EKS Pod Identity** is AWS's newer mechanism. It uses the EKS Pod Identity Agent add-on, and roles are linked to ServiceAccounts through *pod identity associations* in the EKS API. The trust policy is a fixed principal (`pods.eks.amazonaws.com`), so there's no per-cluster OIDC provider and no trust-policy edits when clusters are recreated. AWS recommends it for new EKS workloads.

## Consequences
- Credentials are least-privilege, scoped to a ServiceAccount and short-lived. Node roles stay minimal.
- IRSA works on any Kubernetes cluster with a public OIDC issuer, not just EKS, and it is the mechanism most existing codebases, Helm charts and docs use.
- Each cluster recreation creates a new OIDC issuer URL, so trust policies must be recreated too (Terraform handles this).
- Migrating to Pod Identity later is a contained change: add the agent add-on, create associations, and update the trust policies.

## Alternatives considered
- **EKS Pod Identity:** simpler to operate, and a strong candidate for a later ADR once IRSA is in place. Not every add-on chart documents it equally well yet.
- **Node instance role:** simple, but every pod on the node gets every permission.
- **Static access keys in Secrets:** long-lived credentials. Never.
