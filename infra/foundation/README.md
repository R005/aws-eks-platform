# foundation

Terraform stack for the persistent resources the applications depend on: the `api` image repository in ECR, the database password in AWS Secrets Manager, the Route 53 public hosted zone for `lab.<domain>` and its ACM certificate. Like [`bootstrap`](../bootstrap/README.md), it is applied once and kept. It is **not** part of `make up` / `make down`, so images, the secret, the DNS delegation and the certificate survive cluster teardown.

State: `foundation/terraform.tfstate` in the bucket created by `bootstrap`. It has no dependency on the `network`, `eks` or `addons` stacks.

## Design

- **Immutable image tags.** `image_tag_mutability = "IMMUTABLE"`: a tag (the short Git SHA, see `make image`) always refers to the same image, so a deployed tag can never change under a running release. Pushing an existing tag fails.
- **Scan on push.** ECR basic scanning checks every pushed image for OS package CVEs. Python package CVEs need enhanced scanning (Amazon Inspector) or a CI scanner later.
- **Lifecycle policy.** Keeps the 20 most recent images (`ecr_keep_images`), tagged or untagged, and expires the rest, so storage does not grow without bound.
- **Password never in state.** The password comes from the `ephemeral "random_password"` resource (random provider >= 3.7) and is written through the write-only argument `secret_string_wo` of `aws_secretsmanager_secret_version` (Terraform >= 1.11). Ephemeral values are not saved in the plan or the state, and write-only arguments are sent to AWS but never persisted, so the password only exists in Secrets Manager.
- **Explicit rotation.** Terraform cannot compare a write-only value with what is stored, so it writes the secret only when `secret_string_wo_version` changes. Increase `db_password_version` to generate and store a new password; any other run leaves the stored password untouched.
- **Secret format.** JSON `{"password": "..."}`, read by the `ExternalSecret` in the Helm chart with `property: password`. Other fields (for example a future RDS host) can be added without changing the consumer.
- **Delegated subdomain.** The stack creates a public hosted zone for `lab.<domain>` only, never for the parent domain ([ADR 0010](../../docs/adr/0010-dns-delegated-lab-subdomain.md)). The parent domain stays at its current DNS provider and delegates `lab` to Route 53 with four `NS` records, so automation in this project cannot change other records of the parent domain.
- **Domain kept out of Git.** The parent domain is the `domain_name` variable, set only in the gitignored `terraform.tfvars`. The committed `terraform.tfvars.example` holds the `<domain>` placeholder.
- **Zone kept between sessions.** A recreated zone gets a new set of name servers, which means updating the delegation and waiting for propagation. `force_destroy` is not set, so destroying the zone fails while it still holds records other than `NS` and `SOA`. On top of that, `lifecycle { prevent_destroy = true }` makes Terraform reject any plan that would destroy or replace the zone.
- **One certificate for the subdomain.** ACM issues a certificate for `lab.<domain>` and `*.lab.<domain>`, validated with DNS records in the `lab.<domain>` zone. The wildcard covers every `<app>.lab.<domain>` host, so a new app needs no new certificate. It lives in the cluster's region, because an ALB can only use certificates from its own region.
- **No ARN hand-off.** The AWS Load Balancer Controller finds the certificate by the Ingress host ([ADR 0014](../../docs/adr/0014-ingress-via-aws-load-balancer-controller.md)), so no stack or chart needs its ARN.
- **Validation and renewal.** The apex and the wildcard share one validation CNAME, so the two record instances write the same record (`allow_overwrite`). `aws_acm_certificate_validation` makes the apply wait until the certificate is issued. ACM renews it automatically as long as the CNAME stays in the zone.
- **Access.** The External Secrets Operator IRSA role (`addons` stack) may read `<project>/<env>/*`, which covers `eks-platform/dev/db`. No other role is needed.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_ecr_repository.api` | `eks-platform/api` repository: immutable tags, scan on push, AES256 encryption |
| `aws_ecr_lifecycle_policy.api` | Expires everything beyond the 20 most recent images |
| `aws_secretsmanager_secret.db` | `eks-platform/dev/db` secret (metadata only), 7-day recovery window |
| `ephemeral.random_password.db` | 32-character password, generated per run, never stored |
| `aws_secretsmanager_secret_version.db` | Writes the password through `secret_string_wo`, versioned by `db_password_version` |
| `aws_route53_zone.lab` | Public hosted zone `lab.<domain>`, delegated from the parent domain; `prevent_destroy` |
| `aws_acm_certificate.lab` | Certificate for `lab.<domain>` and `*.lab.<domain>`, DNS validation, `create_before_destroy` |
| `aws_route53_record.lab_cert_validation` | Validation CNAME in the `lab.<domain>` zone (one record, shared by both names) |
| `aws_acm_certificate_validation.lab` | Waits during apply until the certificate is issued |

All resources are tagged through the provider `default_tags`: `Project`, `Env`, `Owner`, `ManagedBy` (`terraform`) and `Stack` (`foundation`).

## Usage

Prerequisites: Terraform >= 1.11, the `bootstrap` stack, and an active AWS SSO session (`aws sso login`).

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner and domain_name
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

### Delegate `lab.<domain>`

A one-time manual step at the parent domain's DNS provider, outside Terraform:

1. Read the name servers: `terraform output lab_zone_name_servers`.
2. At the parent domain's DNS provider, create one `NS` record named `lab` with those four name servers as values.
3. Check the delegation (it can take from minutes up to the parent's `NS` TTL to propagate):

```bash
dig +short NS lab.<domain>                    # returns the four Route 53 name servers
dig +trace lab.<domain> | tail -n 20          # the referral for lab.<domain> comes from the parent's name servers
```

The certificate is validated through this zone, so apply it only once the delegation resolves. Otherwise `aws_acm_certificate_validation` waits until it times out. Check it after apply:

```bash
aws acm list-certificates --query 'CertificateSummaryList[].[DomainName,Status]' --output table   # ISSUED
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
| `domain_name` | (required) | Parent domain; the hosted zone is `lab.<domain_name>`. Set in `terraform.tfvars` only |

## Outputs

| Output | Description |
| --- | --- |
| `ecr_repository_url` | Repository URL used by `make image` and `make deploy` |
| `db_secret_name` | Secret name read by the `ExternalSecret` |
| `lab_zone_name_servers` | The four name servers for the `NS` delegation at the parent domain |
| `lab_zone_name` | `lab.<domain>`; `make deploy` builds the app host from it |

## Cost and teardown

About $0.40 per month for the secret, $0.50 per month for the hosted zone (plus $0.40 per million queries), nothing for the public ACM certificate and $0.10 per GB-month of image storage. The stack is kept between sessions. Removing it intentionally (`terraform destroy`) fails while the repository still holds images, because `force_delete` is not set. Delete the images first. The secret is recoverable for 7 days after deletion. The hosted zone has `prevent_destroy`, so `terraform destroy` fails until that `lifecycle` block is removed in a reviewed change; it also fails while the zone holds records other than `NS` and `SOA`; after a destroy, remove the `lab` `NS` records at the parent domain's DNS provider.
