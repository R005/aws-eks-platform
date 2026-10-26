# eks

Terraform stack that creates the EKS cluster, its managed node group, the IRSA OIDC provider and the core managed add-ons. It uses the community module [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws) (major version 21).

State: `eks/terraform.tfstate` in the bucket created by [`bootstrap`](../bootstrap/README.md). Apply order: `bootstrap → network → eks → addons`, destroy in reverse.

## Design

- **Kubernetes 1.37**, the newest version in EKS standard support at the time of writing (`aws eks describe-cluster-versions`). Versions in extended support cost $0.60/h instead of $0.10/h for the control plane, so upgrades are planned before standard support ends.
- **Network lookup by tag, not remote state.** The VPC is found by its `Name` (`<project>-<env>-vpc`), `Project` and `Env` tags, and the private subnets by `kubernetes.io/role/internal-elb = 1`. The stack does not read the `network` state file, so the two stacks share no state permissions and no output contract. A postcondition fails the plan early when fewer than two private subnets are found.
- **Nodes in private subnets.** The node group and the control plane ENIs use the private subnets. Nodes reach the internet through the NAT Gateway.
- **Managed node group:** 2 x `t3.large` on-demand, Amazon Linux 2023 (`AL2023_x86_64_STANDARD`, amd64, see [ADR 0006](../../docs/adr/0006-amd64-nodes-multi-arch-images.md)), min 2 / max 3. `desired_size` is only used at creation, so a cluster autoscaler can own it later. IMDSv2 is required with a hop limit of 1, so pods cannot use the node's instance credentials.
- **API endpoint:** public and private. Public access lets `kubectl` and CI reach the API. It is open to `0.0.0.0/0`, but every request still needs IAM authentication and an access entry. Restricting `endpoint_public_access_cidrs` is a later hardening step.
- **IRSA:** the module creates the IAM OIDC identity provider for the cluster issuer ([ADR 0005](../../docs/adr/0005-irsa-for-pod-aws-access.md)). The `addons` stack builds its per-controller IAM roles on the `oidc_provider_arn` output.
- **Managed add-ons:** `vpc-cni` (installed before the node group, otherwise nodes never become `Ready`), `kube-proxy` and `coredns`, each at the latest version compatible with the cluster version.
- **Access entries only** ([ADR 0013](../../docs/adr/0013-eks-access-entries-only.md)). `authentication_mode = "API"`: cluster access is managed through the EKS API, not the `aws-auth` ConfigMap. The IAM Identity Center `AdministratorAccess` role gets `AmazonEKSClusterAdminPolicy` at cluster scope. The role is found with a data source (`AWSReservedSSO_<permission-set>_<suffix>` under `/aws-reserved/sso.amazonaws.com/`), and its ARN is never written in code. `enable_cluster_creator_admin_permissions` is `false`, so admin access does not depend on who ran `apply`.
- **Module defaults kept:** Kubernetes Secrets are envelope-encrypted with a dedicated KMS key, and the control plane `api`, `audit` and `authenticator` logs go to CloudWatch Logs with 90-day retention.

## Resources

All resources come from `module.eks` (36 in total):

| Resource | Purpose |
| --- | --- |
| `aws_eks_cluster.this` | EKS control plane |
| `aws_iam_role.this` + 2 attachments, `aws_iam_policy.cluster_encryption` | Cluster IAM role: `AmazonEKSClusterPolicy` and use of the secrets KMS key |
| `module.kms` (`aws_kms_key`, `aws_kms_alias`) | KMS key for envelope encryption of Kubernetes Secrets |
| `aws_cloudwatch_log_group.this` | `/aws/eks/<cluster>/cluster` control plane logs, 90-day retention |
| `aws_security_group.cluster`, `aws_security_group.node` + rules | Control plane and node security groups: API on 443, kubelet, CoreDNS, webhook ports, node-to-node ephemeral ports |
| `aws_iam_openid_connect_provider.oidc_provider` | IAM OIDC provider for IRSA |
| `aws_eks_addon.before_compute["vpc-cni"]` | Amazon VPC CNI, created before the nodes |
| `aws_eks_addon.this["kube-proxy"]`, `aws_eks_addon.this["coredns"]` | kube-proxy and CoreDNS |
| `aws_eks_access_entry.this["sso_admin"]` | Access entry for the SSO administrator role |
| `aws_eks_access_policy_association.this["sso_admin_cluster_admin"]` | Grants `AmazonEKSClusterAdminPolicy` at cluster scope |
| `module.eks_managed_node_group["default"]`: `aws_eks_node_group`, `aws_launch_template`, `aws_iam_role` + 3 attachments | Managed node group, its launch template (IMDSv2) and node IAM role (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`) |
| `time_sleep.this`, `null_resource.validate_cluster_service_cidr` | Module helpers: wait for the cluster to settle, validate the service CIDR |

| Data source | Purpose |
| --- | --- |
| `aws_vpc.this` | Finds the VPC by tags |
| `aws_subnets.private` | Finds the private subnets by the `internal-elb` role tag |
| `aws_iam_roles.sso_admin` | Finds the SSO `AdministratorAccess` role; fails unless exactly one matches |
| `aws_partition.current` | Builds the access policy ARN without hardcoding the partition |

All resources are tagged through the provider `default_tags`: `Project`, `Env`, `Owner`, `ManagedBy` (`terraform`) and `Stack` (`eks`).

## Usage

Prerequisites: Terraform >= 1.11, the `network` stack applied, and an active AWS SSO session with the `AdministratorAccess` permission set (`aws sso login`).

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner
cp backend.hcl.example backend.hcl             # replace <account-id>

terraform init -backend-config=backend.hcl
terraform plan -out=tfplan                     # fails with "no matching EC2 VPC found" until network is applied
terraform apply tfplan
```

From the repository root, `make up` applies `network` and then this stack. Creating the cluster takes about 15 minutes.

Connect `kubectl`:

```bash
$(terraform output -raw configure_kubectl)
kubectl get nodes
```

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | (required) | AWS region, same as the `network` stack |
| `owner` | (required) | Owner tag |
| `project` | `eks-platform` | Name prefix and `Project` tag |
| `env` | `dev` | Name part and `Env` tag |
| `kubernetes_version` | `1.37` | EKS Kubernetes version |
| `node_instance_types` | `["t3.large"]` | Node instance types (amd64) |
| `node_min_size` / `node_max_size` / `node_desired_size` | `2` / `3` / `2` | Node group size |
| `admin_permission_set_name` | `AdministratorAccess` | Permission set whose SSO role gets cluster-admin |

## Outputs

| Output | Description |
| --- | --- |
| `cluster_name` | Cluster name (`<project>-<env>`) |
| `cluster_endpoint` | Kubernetes API endpoint |
| `cluster_version` | Kubernetes version |
| `oidc_provider_arn` | IAM OIDC provider ARN, used for IRSA roles |
| `cluster_security_group_id` | Cluster security group ID |
| `node_security_group_id` | Node security group ID |
| `configure_kubectl` | `aws eks update-kubeconfig` command for this cluster |

## Cost and teardown

About $0.27 per hour while it exists:

| Item | Approx. cost |
| --- | --- |
| EKS control plane (standard support) | $0.10/h |
| 2 x `t3.large` on-demand | 2 x $0.0832/h = $0.166/h |
| 2 x 20 GB gp3 root volumes | about $0.004/h |
| KMS key, CloudWatch Logs | about $1/month plus log ingestion |

Destroy it at the end of every session, before the `network` stack:

```bash
make down    # from the repository root: destroys eks, then network
```

The secrets KMS key is scheduled for deletion with the default 30-day waiting period rather than deleted immediately. A key pending deletion is not billed. Each recreated cluster gets a new key.
