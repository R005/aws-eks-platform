# 0006. x86 (amd64) worker nodes with multi-arch image builds

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
The development machine is an Apple Silicon Mac, so `docker build` produces **arm64** images by default. If an arm64-only image runs on an amd64 node, the container crashes with `exec format error`. We need one image that runs both locally and in the cluster.

## Decision
- EKS managed node group on **x86 (amd64)** instances (for example `t3.medium`).
- Images are built as **multi-arch manifests** (`linux/amd64,linux/arm64`) with `docker buildx`, and pushed to ECR:
  `docker buildx build --platform linux/amd64,linux/arm64 -t <account-id>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag> --push .`
- CI is the normal build path. GitLab.com shared runners are amd64 ([ADR 0008](0008-gitlab-shared-runners.md)), so they build arm64 under QEMU emulation.
- Base images must be multi-arch (official `python:3.x-slim` images are).

## Consequences
- The same tag runs on the Mac and on the nodes, because the runtime pulls the matching architecture.
- Emulated cross-arch builds are slower, especially when building Python wheels.
- amd64 instances are widely available and every add-on image supports them.

## Alternatives considered
- **Graviton (arm64) nodes:** about 20% cheaper for similar performance, and native for Mac builds. A good production option, but CI runners are amd64, and amd64 is the most widely supported default.
- **amd64-only builds (`--platform linux/amd64`):** simpler, but the image would run under emulation on the Mac.
- **Mixed-architecture node groups:** more realistic at scale, but scheduling and node selectors add complexity the lab doesn't need.
