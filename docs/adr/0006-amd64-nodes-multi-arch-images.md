# 0006. x86 (amd64) worker nodes with multi-arch image builds

Status: Accepted, 2026-10-25

## Context

Development happens on an Apple Silicon Mac, so `docker build` produces arm64 images. An arm64-only image fails on an amd64 node with `exec format error`.

## Decision

Run the managed node group on amd64 instances. Build images as multi-arch manifests (`linux/amd64,linux/arm64`) with `docker buildx` and push them to ECR. CI is the normal build path; its amd64 shared runners ([ADR 0008](0008-gitlab-shared-runners.md)) build arm64 under emulation. Base images must be multi-arch.

## Consequences

The same tag runs on the Mac and on the nodes. Emulated builds are slower. amd64 is supported by every add-on image. Graviton would be about 20% cheaper and is a good production option, but CI runners are amd64.
