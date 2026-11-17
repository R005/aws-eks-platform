# eks

The EKS cluster, its managed node group, the IRSA OIDC provider and the core add-ons, built with [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws) v21.

## Design

Kubernetes 1.37, the newest version in standard support. Extended support costs $0.60/h instead of $0.10/h, so upgrades happen before standard support ends.

The VPC and private subnets are found by tag, not through the `network` state. A postcondition fails the plan if fewer than two private subnets are found.

The node group is 2 x `t3.large` on demand, Amazon Linux 2023 on amd64 ([ADR 0006](../../docs/adr/0006-amd64-nodes-multi-arch-images.md)), min 2, max 3. `desired_size` only applies at creation, so an autoscaler can own it later. IMDSv2 has a hop limit of 1, so pods cannot use the node's credentials.

The API endpoint is public, for `kubectl` and CI, and private, for the nodes. Every request still needs IAM authentication and an access entry. Restricting the public CIDRs is a later hardening step.

Access uses access entries only, with no `aws-auth` ConfigMap ([ADR 0013](../../docs/adr/0013-eks-access-entries-only.md)). The IAM Identity Center `AdministratorAccess` role gets `AmazonEKSClusterAdminPolicy`. The role is looked up by name pattern, so its ARN never appears in code. Creator admin is off, so access does not depend on who ran the apply.

`vpc-cni` is installed before the nodes, which never become Ready without it. `kube-proxy` and `coredns` follow at the latest compatible versions. Module defaults are kept for KMS envelope encryption of Secrets and for control plane logs in CloudWatch (90 days).

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner
cp backend.hcl.example backend.hcl             # replace <account-id>
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan                     # fails until network is applied
terraform apply tfplan                         # about 15 minutes
$(terraform output -raw configure_kubectl)
kubectl get nodes
```

Normally `make up` applies it between `network` and `addons`.

## Cost and teardown

About $0.27 per hour: $0.10 for the control plane, $0.17 for the two nodes and a little for root volumes, the KMS key and logs. `make down` destroys it after `addons`. The secrets KMS key goes into its 30-day deletion window, and a key pending deletion is not billed.
