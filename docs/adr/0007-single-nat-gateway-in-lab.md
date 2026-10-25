# 0007. Single NAT Gateway in the lab (per-AZ in production)

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
Worker nodes run in private subnets across 2 AZs and need outbound internet access (pulling images, AWS APIs without VPC endpoints, package installs). A NAT Gateway costs about $0.045/h (about $33/month) **per gateway**, plus data processing charges.

## Decision
- **Lab:** one NAT Gateway in a single public subnet, with every private subnet's route table pointing at it (`single_nat_gateway = true` style).
- **Production:** one NAT Gateway **per AZ**, with each private subnet routing to the NAT in its own AZ. This is a variable in the `network` stack, so it's a configuration change rather than a code change.

## Consequences
- Saves about $33/month for each AZ beyond the first.
- **A single point of failure:** if that AZ or its NAT has problems, nodes in *every* AZ lose egress.
- Traffic from the other AZ crosses AZs to reach the NAT, which adds cross-AZ data charges and a little latency.

## Alternatives considered
- **NAT per AZ:** the correct production design, but it doubles NAT cost in the lab.
- **VPC endpoints only (ECR, S3, STS, etc.):** cuts NAT traffic, and some endpoints are worth adding later. Interface endpoints cost per hour per AZ too, and don't cover the general internet.
- **NAT instance:** cheaper, but we would have to patch, scale and make it highly available ourselves.
- **Public subnets for nodes:** no NAT needed, but nodes would be exposed directly.
