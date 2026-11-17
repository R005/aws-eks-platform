# 0003. S3 native state locking for Terraform

Status: Accepted, 2026-10-25

## Context

Terraform state must be remote and locked, so two applies, for example from a laptop and from CI, cannot corrupt it. The classic S3 backend locks through a DynamoDB table. Terraform 1.10 added `use_lockfile`, which writes a `.tflock` object next to the state with an S3 conditional write, and 1.11 deprecated DynamoDB locking.

## Decision

Use the S3 backend with `use_lockfile = true` and no DynamoDB table, and require Terraform 1.11 or later. The `bootstrap` stack creates the bucket. Each stack has its own state key, and backend settings are passed with `-backend-config`, not hardcoded.

## Consequences

There is one less resource to create, secure and pay for. IAM needs object read, write and delete on the `.tflock` objects. Terraform older than 1.10 cannot use the backend. A stuck lock is still cleared with `terraform force-unlock`. State stays in our AWS account rather than in HCP Terraform or GitLab.
