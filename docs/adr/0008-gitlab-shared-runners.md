# 0008. GitLab.com shared runners

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
The pipeline lints, tests, builds and pushes images, and deploys with Helm. Jobs need a runner. We want no runner infrastructure to maintain, and nothing running (and costing money) between sessions.

## Decision
Use **GitLab.com hosted (shared) Linux runners** (amd64), with no self-hosted runners.

- Image builds use Docker-in-Docker (or buildx with a QEMU setup) on the shared runner ([ADR 0006](0006-amd64-nodes-multi-arch-images.md)).
- AWS access from CI uses short-lived credentials, not static keys. The exact method (for example GitLab OIDC ID tokens and `AssumeRoleWithWebIdentity`) is decided at roadmap M8.
- The deploy job reaches the EKS API over its public endpoint, restricted by IAM/access entries.

## Consequences
- No runner hosts to patch, scale or pay for. Jobs run on clean, ephemeral VMs.
- Compute minutes are limited by the GitLab plan quota, so pipelines should cache dependencies and avoid unnecessary jobs.
- Runner egress IPs are shared and change, so the EKS public endpoint can't be locked to a CIDR allowlist.
- Docker-in-Docker needs privileged mode, which hosted runners provide.

## Alternatives considered
- **Self-hosted runner on EKS (GitLab Runner Helm chart):** private network access to the cluster and no minute quota, but it's more to operate, and the runner dies whenever the lab is destroyed.
- **Self-hosted runner on EC2:** the same benefits plus an always-on cost.
- **GitHub Actions:** also viable. GitLab CI is the target stack for this project.
