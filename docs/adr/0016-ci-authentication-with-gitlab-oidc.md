# 0016. CI authentication with GitLab OIDC

Status: Accepted, 2026-11-22

## Context

The pipeline pushes images to ECR and deploys to EKS from GitLab.com shared runners ([ADR 0008](0008-gitlab-shared-runners.md)). Stored access keys would be long-lived, readable by anyone who can change the pipeline, and need rotating. The runners have no static IPs: they run in two Google Cloud regions with 66 IPv4 ranges, more than the 40 public access CIDRs an EKS cluster allows.

## Decision

Jobs on `main` request a GitLab ID token (`id_tokens`, audience `https://gitlab.com`) and the AWS CLI exchanges it with `AssumeRoleWithWebIdentity` for one role. The `foundation` stack owns the gitlab.com OIDC provider and the role. Its trust policy requires that audience and the exact subject `project_path:<group>/aws-eks-platform:ref_type:branch:ref:main`. Its IAM policy allows pushing to the `eks-platform/api` repository and `eks:DescribeCluster` on `eks-platform-dev`, nothing else.

In the cluster, an access entry gives the role `AmazonEKSEditPolicy` in the `tasks` namespace only, plus a Kubernetes group bound to a Role for `ExternalSecret` and `SecretStore`, which the edit policy does not cover. The namespace is created by the `addons` stack. The public endpoint stays open to `0.0.0.0/0`; every request still needs IAM authentication and the access entry.

## Consequences

No AWS secret is stored in GitLab, and credentials last one hour at most. Merge request and branch pipelines cannot assume the role, even if their pipeline file is changed. CI cannot touch other namespaces, cluster-scoped resources or RBAC. An endpoint allowlist is not possible with shared runners; a runner inside the VPC or a private endpoint would allow one later. Renaming the GitLab project or the default branch breaks the trust until `gitlab_project_path` is updated.
