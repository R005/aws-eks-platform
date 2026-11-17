# bootstrap

The S3 bucket and KMS key that hold Terraform state for every other stack. Applied once per account and kept.

The bucket is named `<project>-tfstate-<account-id>-<region>`, encrypted with a customer-managed KMS key, versioned, closed to public access and HTTPS-only. Locking uses S3 lock files, so there is no DynamoDB table ([ADR 0003](../../docs/adr/0003-s3-native-state-locking.md)). `prevent_destroy` protects the bucket. The KMS key has a 7-day deletion window, a lab value; production would keep 30 days.

## Configuration

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner
cp backend.hcl.example backend.hcl             # replace <account-id>
```

`backend.hcl` is gitignored because the bucket name contains the account ID. The bucket in it must match the `state_bucket_name` output.

## First apply in a new account

The bucket cannot hold its own state before it exists, so the first apply uses local state and then migrates it.

```bash
cat > backend_override.tf <<'EOF'
terraform {
  backend "local" {}
}
EOF
terraform init
terraform apply
terraform output state_bucket_name             # put this in backend.hcl

rm backend_override.tf
terraform init -backend-config=backend.hcl -migrate-state
terraform plan                                 # expect no changes
```

`backend_override.tf` is gitignored. Once the plan is clean, delete the local `terraform.tfstate` and `terraform.tfstate.backup`.

## Later runs

```bash
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

## Teardown

Kept when the platform is destroyed; it costs about $1 per month, mostly the KMS key. Removing it means deleting the `prevent_destroy` rule, migrating the state back to local and emptying every object version from the bucket.
