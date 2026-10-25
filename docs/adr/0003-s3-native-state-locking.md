# 0003. S3 native state locking for Terraform

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
Terraform state must be remote (shared, durable) and **locked**, so that two `apply` runs (for example a laptop and CI) can't write the same state at once and corrupt it.

**How DynamoDB locking works (the classic approach):** the S3 backend is given a `dynamodb_table`. Before an operation, Terraform does a *conditional* `PutItem` that only succeeds if no item with that `LockID` (the bucket/key path) exists. If the item already exists, the lock is held and Terraform waits or fails. The item is deleted when the operation ends. This means a second AWS service and its own IAM permissions.

**S3 native locking:** Terraform 1.10 added `use_lockfile = true`. Terraform creates a `<state-key>.tflock` object next to the state using an S3 **conditional write** (`If-None-Match`), so creation fails if the lock object already exists. Terraform 1.11 deprecated DynamoDB-based locking.

## Decision
Use the S3 backend with **`use_lockfile = true`** and no DynamoDB table. Require Terraform **>= 1.11**.

- The state bucket is created by the `bootstrap` stack (which itself uses local state the first time) with versioning, SSE encryption, public access blocked, and TLS-only access.
- Each stack (`network`, `eks`, `addons`) has its own state key, which keeps the blast radius small.
- Backend settings (bucket, key, region) are passed at `terraform init` through `-backend-config`, not hardcoded.

## Consequences
- One fewer resource to create, secure and pay for.
- IAM needs `s3:GetObject`, `s3:PutObject` and `s3:DeleteObject` on the `.tflock` objects.
- Older Terraform versions (< 1.10) can't use this backend configuration.
- A stuck lock is cleared with `terraform force-unlock <id>`, the same as before.

## Alternatives considered
- **S3 + DynamoDB locking:** works, and is still very common in existing codebases, but it's deprecated and needs an extra table.
- **HCP Terraform / Terraform Cloud remote state:** a hosted service, which is a dependency and account outside AWS.
- **GitLab-managed Terraform state:** a good fit with GitLab, but it ties state to the CI provider. Keeping state in our AWS account is more portable.
