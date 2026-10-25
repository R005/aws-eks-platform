# 0010. DNS: delegate `lab.<domain>` to Route 53

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
The apps need real hostnames for TLS (ACM) and for Gateway API routing. The parent domain `<domain>` is managed by an existing DNS provider, which may not be Route 53, and other records there must not be affected by lab automation.

## Decision
- Create a **Route 53 public hosted zone for `lab.<domain>`** with Terraform.
- **Delegate** it by adding `NS` records for `lab` at the parent `<domain>` DNS provider, pointing to the zone's four Route 53 name servers. This is a one-time step at the registrar, documented and not automated.
- Apps use **`<app>.lab.<domain>`** (for example `tasks.lab.<domain>`).
- **ExternalDNS** manages records only in this zone (`--domain-filter=lab.<domain>`, a TXT owner registry, and an IAM policy scoped to this hosted zone ID).
- **ACM** certificates (for example `*.lab.<domain>`) are validated with DNS records in this zone.

## Consequences
- Lab automation can never change the parent domain, which limits the blast radius.
- The hosted zone ($0.50/month) is **kept** across lab teardowns. Recreating it would change the name servers and require re-delegation and propagation time.
- The zone's lifecycle is separate from the cluster's, so it lives in its own stack or is excluded from the per-session destroy.

## Alternatives considered
- **Move the whole `<domain>` to Route 53:** simpler, but it gives lab automation access to production DNS.
- **nip.io / sslip.io or raw ALB hostnames:** no real TLS certificates through ACM, and nothing like production.
- **A separate throwaway domain:** works, but costs a domain registration and is further from how real organisations delegate subdomains.
