# 0005. IRSA for pod AWS access

Status: Accepted, 2026-10-25

## Context

Several controllers call AWS APIs: the Load Balancer Controller, ExternalDNS, External Secrets and the EBS CSI driver. Putting their permissions on the node role would give them to every pod on the node.

## Decision

Use IAM Roles for Service Accounts. The `eks` stack creates the cluster's IAM OIDC provider. Each workload gets its own role, trusted only for `system:serviceaccount:<namespace>:<name>` with `aud = sts.amazonaws.com`, and its ServiceAccount is annotated with the role ARN.

## Consequences

Credentials are short-lived and scoped to one ServiceAccount, and node roles stay minimal. IRSA is what most charts and docs use. Each recreated cluster gets a new issuer URL, so trust policies are recreated too, which Terraform handles. EKS Pod Identity is simpler to operate and is the likely successor; moving to it later is a contained change.
