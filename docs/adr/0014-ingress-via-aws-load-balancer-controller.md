# 0014. Ingress via AWS Load Balancer Controller

- **Status:** Accepted
- **Date:** 2026-11-10
- **Supersedes:** [ADR 0011](0011-gateway-api-for-ingress.md)

## Context
External (north-south) HTTPS traffic must reach the `api` service at `tasks.lab.<domain>`. [ADR 0011](0011-gateway-api-for-ingress.md) chose Gateway API on the AWS Load Balancer Controller (LBC), with Ingress as the documented fallback.

The project now has a single public service, so Gateway API's split between a platform-owned `Gateway` and app-owned `HTTPRoute`s has little to separate. Ingress on LBC is the more mature path on EKS: it is enabled by default, needs no extra CRDs, and its features (ACM certificate discovery, HTTP→HTTPS redirect, IP targets, health checks) are stable and widely documented. ExternalDNS reads Ingress hosts without extra configuration.

## Decision
Use **Kubernetes Ingress**, implemented by the **AWS Load Balancer Controller**, which provisions an internet-facing **ALB**.

- The `task-tracker` chart ships an `Ingress` with `ingressClassName: alb` (the `IngressClass` created by the LBC chart).
- Annotations: `scheme: internet-facing`, `target-type: ip` (traffic goes straight to pod IPs, no NodePort hop), listeners on HTTP 80 and HTTPS 443 with `ssl-redirect: '443'`, and the health check on `/readyz`.
- **TLS:** an ACM certificate for `lab.<domain>` and `*.lab.<domain>` (`foundation` stack), validated with DNS records in the `lab.<domain>` zone ([ADR 0010](0010-dns-delegated-lab-subdomain.md)). LBC attaches it through **certificate discovery** by the Ingress rule host, so no certificate ARN is set in the chart or at deploy time.
- **DNS:** ExternalDNS (`addons` stack) creates the record for the Ingress host in the `lab.<domain>` zone only.
- The host is supplied at deploy time (`make deploy`), so the domain is never committed.

## Consequences
- Fewer moving parts: no Gateway API CRDs and no LBC Gateway feature flag. The ALB setup is a set of well-documented annotations.
- Annotations are LBC-specific and not portable to another controller. That is acceptable while the platform is AWS-only.
- No typed separation between platform and app ownership. Several apps can share one ALB later with the `group.name` annotation (IngressGroup).
- A move to Gateway API remains possible later through a new ADR. The ALB, the ACM certificate and ExternalDNS stay the same.

## Alternatives considered
- **Gateway API on LBC (ADR 0011):** the direction the ecosystem is moving in, but its role split brings little value for one public service, and LBC's Gateway support is newer than its Ingress support.
- **ingress-nginx or Envoy Gateway behind an NLB, with cert-manager:** more in-cluster components and Let's Encrypt instead of ACM. ingress-nginx is being retired.
