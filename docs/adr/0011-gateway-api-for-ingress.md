# 0011. Gateway API via AWS Load Balancer Controller

Status: Superseded by [0014](0014-ingress-via-aws-load-balancer-controller.md), 2026-10-25

## Context

External HTTPS traffic had to reach a `web` service. Gateway API separates the platform-owned `Gateway` from app-owned `HTTPRoute`s and uses typed fields instead of controller-specific Ingress annotations.

## Decision

Use Gateway API implemented by the AWS Load Balancer Controller, which provisions an ALB. The platform owns a shared `Gateway` with an ACM certificate for `*.lab.<domain>`, and each app ships an `HTTPRoute`. The controller version is pinned, because its Gateway support is newer than its Ingress support.

## Consequences

Responsibilities are cleanly split and configuration is typed. There are fewer examples than for Ingress, and some features may lag. The fallback is Ingress on the same controller, through a superseding ADR.
