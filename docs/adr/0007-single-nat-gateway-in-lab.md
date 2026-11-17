# 0007. Single NAT Gateway in the lab

Status: Accepted, 2026-10-25

## Context

Nodes in private subnets across two AZs need outbound internet access. Each NAT Gateway costs about $33 per month plus data processing.

## Decision

The lab uses one NAT Gateway, and every private subnet routes through it. Production uses one per AZ. This is a variable in the `network` stack, not a code change.

## Consequences

It saves about $33 per month for each extra AZ. The NAT Gateway is a single point of failure: if its AZ has problems, every AZ loses egress. Traffic from the other AZ pays cross-AZ data charges. VPC endpoints may be added later to cut NAT traffic.
