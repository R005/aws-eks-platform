# 0011. Gateway API via AWS Load Balancer Controller

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
External (north-south) HTTPS traffic must reach the `web` service. Kubernetes offers two APIs for this:

- **Ingress:** a single resource whose advanced behaviour depends on controller-specific annotations, which aren't portable, with no clear split between platform and app ownership.
- **Gateway API:** the successor to Ingress. It's role-oriented: `GatewayClass` (the infrastructure provider), `Gateway` (owned by the platform team: listeners, TLS) and `HTTPRoute` (owned by app teams: hosts, paths, backends). Routing features are typed fields rather than annotations.

## Decision
Use **Gateway API**, implemented by the **AWS Load Balancer Controller (LBC)**, which provisions an **ALB** for HTTP routes.

- The `addons` stack installs the Gateway API CRDs and LBC (with the Gateway API feature enabled), and an IRSA role for LBC ([ADR 0005](0005-irsa-for-pod-aws-access.md)).
- The platform owns a shared `Gateway` with an HTTPS listener using an **ACM** certificate for `*.lab.<domain>` ([ADR 0010](0010-dns-delegated-lab-subdomain.md)), plus an HTTP→HTTPS redirect.
- Each app chart ships an `HTTPRoute` for `<app>.lab.<domain>`. ExternalDNS creates the Route 53 records.
- LBC's Gateway API support is newer than its Ingress support, so we **pin the LBC chart version** and check the supported features and configuration (certificate attachment, target type) against the LBC docs at roadmap M9.

## Consequences
- Platform and app responsibilities are cleanly separated. Configuration is portable and typed rather than a pile of annotations.
- An AWS-native managed ALB, with the same controller we'd use for Ingress anyway.
- There are fewer examples and blog posts than for Ingress + LBC, and some features may lag behind the Ingress implementation.
- Fallback: if a needed feature is missing, switch to Ingress + LBC (the same ALB, a different API) through a superseding ADR.

## Alternatives considered
- **Ingress + AWS LBC + ACM:** the most documented option on EKS. Rejected in favour of the API the ecosystem is moving to.
- **Envoy Gateway (or ingress-nginx) + cert-manager behind an NLB:** a mature, portable Gateway API implementation, but more in-cluster components and Let's Encrypt instead of ACM. Note that ingress-nginx is being retired.
- **AWS Gateway API Controller (VPC Lattice):** targets service-to-service networking across VPCs and accounts, not internet-facing ingress.
