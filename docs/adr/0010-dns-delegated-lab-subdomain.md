# 0010. DNS: delegate `lab.<domain>` to Route 53

Status: Accepted, 2026-10-25

## Context

The apps need real hostnames for ACM certificates and routing. The parent domain is managed by an existing DNS provider, and lab automation must not affect its other records.

## Decision

Terraform creates a Route 53 public hosted zone for `lab.<domain>`. The parent domain delegates to it with `NS` records, a one-time manual step. Apps use `<app>.lab.<domain>`. ExternalDNS manages records only in this zone, through a domain filter, a TXT owner registry and an IAM policy scoped to the zone. ACM certificates are validated with records in this zone.

## Consequences

Lab automation can never change the parent domain. The zone ($0.50 per month) is kept across teardowns, because a recreated zone gets new name servers and needs re-delegation, so it lives outside the per-session stacks.
