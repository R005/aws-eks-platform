# 0014. Ingress via AWS Load Balancer Controller

Status: Accepted, 2026-11-10. Supersedes [ADR 0011](0011-gateway-api-for-ingress.md).

## Context

HTTPS traffic must reach the `api` at `tasks.lab.<domain>`. ADR 0011 chose Gateway API with Ingress as the fallback. The project now has a single public service, so Gateway API's split between platform and app ownership has little to separate. Ingress on the Load Balancer Controller is enabled by default, needs no extra CRDs, and its certificate discovery, redirects, IP targets and health checks are stable and well documented.

## Decision

Use Kubernetes Ingress with the AWS Load Balancer Controller, which provisions an internet-facing ALB. The chart's Ingress uses `ingressClassName: alb`, IP targets, listeners on 80 and 443 with a redirect, and a `/readyz` health check. The ACM certificate for `lab.<domain>` and `*.lab.<domain>` comes from the `foundation` stack and is attached by certificate discovery, so no ARN is set. ExternalDNS creates the record. The host is supplied at deploy time, so the domain is never committed.

## Consequences

There are no Gateway API CRDs or feature flags, just documented annotations. Those annotations are specific to this controller, which is acceptable while the platform is AWS-only. Several apps can share one ALB later with an IngressGroup. A move to Gateway API stays possible through a new ADR, keeping the ALB, certificate and ExternalDNS.
