# bootstrap

Terraform stack that creates the remote state storage used by every other stack in this repository (`network`, `eks`, `addons`). It is applied once per AWS account and kept for the lifetime of the platform.

See [ADR 0003](../../docs/adr/0003-s3-native-state-locking.md) for the state and locking design.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_kms_key.tfstate` | Customer-managed key that encrypts the state, with yearly key rotation |
| `aws_kms_alias.tfstate` | Friendly name `alias/<project>-tfstate` for the key |
| `aws_s3_bucket.tfstate` | State bucket, named `<project>-tfstate-<account-id>-<region>` |
| `aws_s3_bucket_versioning.tfstate` | Keeps every previous state version |
| `aws_s3_bucket_server_side_encryption_configuration.tfstate` | Default SSE-KMS encryption with the key above, S3 Bucket Key enabled |
| `aws_s3_bucket_public_access_block.tfstate` | Blocks all public ACLs and policies |
| `aws_s3_bucket_policy.tfstate` | Denies any request not made over HTTPS |

| Data source | Purpose |
| --- | --- |
| `aws_caller_identity.current` | Reads the account ID, so the bucket name is unique without hardcoding it |
| `aws_iam_policy_document.tfstate` | Builds the HTTPS-only bucket policy JSON |

All resources are tagged through the provider `default_tags`: `Project`, `Env` (`shared`), `Owner`, `ManagedBy` (`terraform`) and `Stack` (`bootstrap`).

## Security settings

- **KMS encryption.** Objects are encrypted by default with a customer-managed KMS key (`aws:kms`), so key usage is controlled by its key policy and auditable in CloudTrail. Key rotation is enabled. The S3 Bucket Key reduces KMS request volume and cost.
- **Versioning.** Every state write keeps the previous version, so a corrupted or accidentally overwritten state can be restored.
- **Public access blocked.** All four public access block settings are enabled. State can contain sensitive values and must never be public.
- **HTTPS-only policy.** The bucket policy denies all `s3:*` actions when `aws:SecureTransport` is `false`. It is applied after the public access block.
- **Native locking.** The backend uses `use_lockfile = true`: Terraform writes a `.tflock` object next to the state with an S3 conditional write, so no DynamoDB table is needed. Requires Terraform >= 1.11.
- **`prevent_destroy`.** The bucket has `lifecycle { prevent_destroy = true }`, so Terraform rejects any plan that would delete it.

The KMS key uses a 7-day deletion window to keep teardown of the sandbox account short. A production account would normally keep the 30-day default.

## How the bootstrap works

The state bucket cannot store its own state before it exists, so the stack is created in two phases:

1. **Create with local state.** The first `apply` runs with a local backend and writes `terraform.tfstate` on disk.
2. **Migrate into the bucket.** The S3 backend is then initialized against the new bucket, and `terraform init -migrate-state` copies the local state to `bootstrap/terraform.tfstate` in that bucket. From then on the stack manages itself from remote state with locking.

Backend settings live in `backend.hcl` (gitignored) because the bucket name contains the account ID. `backend.tf` only declares an empty `backend "s3" {}` block.

## Usage

Prerequisites: Terraform >= 1.11 and an active AWS SSO session for the target account (`aws sso login`).

### Configuration

Create `terraform.tfvars` (gitignored) from the template and set `owner`:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Create `backend.hcl` from the template and replace `<account-id>` with the target account ID:

```bash
cp backend.hcl.example backend.hcl
```

```hcl
bucket       = "eks-platform-tfstate-<account-id>-us-east-1"
key          = "bootstrap/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
```

The bucket name must match the `state_bucket_name` output.

### Existing bucket

When the bucket already exists, initialize against it and work as usual:

```bash
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

### First-time bootstrap in a new account

1. Override the backend with a local one. `backend_override.tf` is gitignored, so no tracked file changes:

   ```bash
   cat > backend_override.tf <<'EOF'
   terraform {
     backend "local" {}
   }
   EOF
   ```

2. Create the resources with local state:

   ```bash
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   terraform output state_bucket_name    # use this value in backend.hcl
   ```

3. Remove the override and migrate the state into the bucket:

   ```bash
   rm backend_override.tf
   terraform init -backend-config=backend.hcl -migrate-state   # answer "yes" to copy the state
   terraform plan                                              # expect: No changes
   ```

4. Once the plan is clean, delete the local copies `terraform.tfstate` and `terraform.tfstate.backup`.

## Outputs

| Output | Description |
| --- | --- |
| `state_bucket_name` | Name of the state bucket, used as `bucket` in every stack's backend config |
| `kms_key_arn` | ARN of the KMS key that encrypts the state |

## Teardown

This stack is kept when the other stacks are destroyed. Its cost is about $1 per month, mostly the KMS key. Removing it intentionally requires deleting the `prevent_destroy` lifecycle rule, migrating the state back to local, and emptying all object versions from the bucket.
