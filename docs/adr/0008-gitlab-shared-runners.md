# 0008. GitLab.com shared runners

Status: Accepted, 2026-10-25

## Context

The pipeline lints, tests, builds images and deploys with Helm. Nothing should need maintaining or cost money between sessions.

## Decision

Use GitLab.com hosted Linux runners (amd64), with no self-hosted runners. Image builds use Docker-in-Docker or buildx on the shared runner ([ADR 0006](0006-amd64-nodes-multi-arch-images.md)). CI reaches AWS with short-lived credentials; the method is decided at M8. The deploy job uses the cluster's public endpoint, restricted by IAM and access entries.

## Consequences

There are no runner hosts to patch or pay for, and jobs run on clean VMs. Minutes are limited by the plan quota, so pipelines should cache. Runner IPs are shared and change, so the public endpoint cannot be locked to an allowlist. A runner on the cluster would die every time the lab is destroyed.
