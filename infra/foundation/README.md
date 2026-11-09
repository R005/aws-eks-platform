# foundation

Terraform stack for the persistent resources the applications depend on: the `api` image repository in ECR and the database password in AWS Secrets Manager. Like [`bootstrap`](../bootstrap/README.md), it is applied once and kept. It is **not** part of `make up` / `make down`, so images and the secret survive cluster teardown.

State: `foundation/terraform.tfstate` in the bucket created by `bootstrap`. It has no dependency on the `network`, `eks` or `addons` stacks.

## Design

- **Immutable image tags.** `image_tag_mutability = "IMMUTABLE"`: a tag (the short Git SHA, see `make image`) always refers to the same image, so a deployed tag can never change under a running release. Pushing an existing tag fails.
- **Scan on push.** ECR basic scanning checks every pushed image for OS package CVEs. Python package CVEs need enhanced scanning (Amazon Inspector) or a CI scanner later.
- **Lifecycle policy.** Keeps the 20 most recent images (`ecr_keep_images`), tagged or untagged, and expires the rest, so storage does not grow without bound.
- **Password never in state.** The password comes from the `ephemeral "random_password"` resource (random provider >= 3.7) and is written through the write-only argument `secret_string_wo` of `aws_secretsmanager_secret_version` (Terraform >= 1.11). Ephemeral values are not saved in the plan or the state, and write-only arguments are sent to AWS but never persisted, so the password only exists in Secrets Manager.
- **Explicit rotation.** Terraform cannot compare a write-only value with what is stored, so it writes the secret only when `secret_string_wo_version` changes. Increase `db_password_version` to generate and store a new password; any other run leaves the stored password untouched.
- **Secret format.** JSON `{"password": "..."}`, read by the `ExternalSecret` in the Helm chart with `property: password`. Other fields (for example a future RDS host) can be added without changing the consumer.
- **Access.** The External Secrets Operator IRSA role (`addons` stack) may read `<project>/<env>/*`, which covers `eks-platform/dev/db`. No other role is needed.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_ecr_repository.api` | `eks-platform/api` repository: immutable tags, scan on push, AES256 encryption |
| `aws_ecr_lifecycle_policy.api` | Expires everything beyond the 20 most recent images |
| `aws_secretsmanager_secret.db` | `eks-platform/dev/db` secret (metadata only), 7-day recovery window |
| `ephemeral.random_password.db` | 32-character password, generated per run, never stored |
| `aws_secretsmanager_secret_version.db` | Writes the password through `secret_string_wo`, versioned by `db_password_version` |

All resources are tagged through the provider `default_tags`: `Project`, `Env`, `Owner`, `ManagedBy` (`terraform`) and `Stack` (`foundation`).

## Usage

Prerequisites: Terraform >= 1.11, the `bootstrap` stack, and an active AWS SSO session (`aws sso login`).

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner
cp backend.hcl.example backend.hcl             # replace <account-id>

terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Check the result without printing the password:

```bash
aws ecr describe-repositories --repository-names eks-platform/api \
  --query 'repositories[0].[imageTagMutability,imageScanningConfiguration.scanOnPush]'
aws secretsmanager describe-secret --secret-id eks-platform/dev/db --query '[Name,LastChangedDate]'
```

### Rotate the database password

```bash
terraform apply -var db_password_version=2    # or set it in terraform.tfvars
```

PostgreSQL reads the password only when it initialises an empty data directory. After a rotation, run `make undeploy` and `make deploy` (the volume is recreated), or change the password inside PostgreSQL to match.

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | (required) | AWS region, same as the cluster |
| `owner` | (required) | Owner tag |
| `project` | `eks-platform` | Name prefix and `Project` tag |
| `env` | `dev` | Secret name part and `Env` tag |
| `ecr_keep_images` | `20` | Images kept per repository |
| `db_password_version` | `1` | Increase to store a newly generated password |

## Outputs

| Output | Description |
| --- | --- |
| `ecr_repository_url` | Repository URL used by `make image` and `make deploy` |
| `db_secret_name` | Secret name read by the `ExternalSecret` |

## Cost and teardown

About $0.40 per month for the secret plus $0.10 per GB-month of image storage. The stack is kept between sessions. Removing it intentionally (`terraform destroy`) fails while the repository still holds images, because `force_delete` is not set. Delete the images first. The secret is recoverable for 7 days after deletion.
