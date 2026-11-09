# addons

Terraform stack that installs the cluster add-ons the platform depends on, each with its own IRSA role where it calls AWS APIs: the EBS CSI driver and a default `gp3` StorageClass, the AWS Load Balancer Controller, External Secrets Operator and metrics-server.

State: `addons/terraform.tfstate` in the bucket created by [`bootstrap`](../bootstrap/README.md). Apply order: `bootstrap → network → eks → addons`, destroy in reverse.

## Design

- **Cluster lookup by name, not remote state.** The cluster is found by name (`<project>-<env>`) and the IAM OIDC provider by the cluster's issuer URL. The stack does not read the `eks` state file, the same pattern the `eks` stack uses for the network.
- **Exec-based Kubernetes auth.** The `helm` and `kubernetes` providers get the endpoint and CA from the `aws_eks_cluster` data source and fetch a short-lived token with `aws eks get-token` on every run, using the caller's AWS credentials. No token is stored in state or in a kubeconfig file. The `helm` provider is on major version 3, where `kubernetes`, `exec` and `set` are attributes rather than blocks.
- **Pinned versions.** Every chart and EKS add-on version is a variable with a pinned default, so upgrades are explicit, reviewed changes. Provider versions are pinned in `.terraform.lock.hcl`.
- **One IRSA role per controller** ([ADR 0005](../../docs/adr/0005-irsa-for-pod-aws-access.md)), built with the `iam-role-for-service-accounts` submodule of [`terraform-aws-modules/iam/aws`](https://registry.terraform.io/modules/terraform-aws-modules/iam/aws) (v6). Each trust policy allows `sts:AssumeRoleWithWebIdentity` only for one exact `system:serviceaccount:<namespace>:<name>` subject, and checks `aud = sts.amazonaws.com`.
- **EBS CSI driver** as an EKS managed add-on, with the AWS-managed `AmazonEBSCSIDriverPolicy`. A `gp3` StorageClass is the cluster default: encrypted, `WaitForFirstConsumer` (the volume is created in the AZ where the pod is scheduled), volume expansion allowed, `Delete` reclaim policy. The `gp2` class EKS creates is left in place and is not marked default.
- **AWS Load Balancer Controller** from its Helm chart in `kube-system`. The IAM policy is the official `iam_policy.json` published with the controller release, vendored in [`policies/`](policies/) with the version in the file name. Bumping `lbc_chart_version` without adding the matching policy file fails the plan. `region` and `vpcId` are passed explicitly, because IMDSv2 with a hop limit of 1 stops pods from discovering them through instance metadata.
- **External Secrets Operator** from its Helm chart in the `external-secrets` namespace, with its CRDs ([ADR 0004](../../docs/adr/0004-external-secrets-operator.md)). The role allows only `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` on secrets named `<project>/<env>/*`. The module's built-in External Secrets policy is not used, because it also grants `secretsmanager:ListSecrets`, `secretsmanager:BatchGetSecretValue` and `ssm:DescribeParameters` on all resources.
- **ClusterSecretStore is not created here.** It is a custom resource, and `kubernetes_manifest` needs the CRD to exist at plan time, which it does not before the first apply. It ships with the app deployment. Without `auth` settings, it uses the operator's own IRSA credentials from the annotated ServiceAccount.
- **metrics-server** as an EKS managed add-on (EKS publishes it), so AWS builds and patches the image. It calls no AWS APIs and has no IAM role.
- **Install order.** The Load Balancer Controller registers a mutating webhook for Services. External Secrets and metrics-server create Services, so they depend on the controller release, which waits until its pods are ready.

## Resources

14 resources:

| Resource | Purpose |
| --- | --- |
| `module.ebs_csi_irsa`: `aws_iam_role`, 1 policy attachment | `<project>-<env>-ebs-csi` role with `AmazonEBSCSIDriverPolicy` |
| `aws_eks_addon.ebs_csi` | `aws-ebs-csi-driver` managed add-on, using the IRSA role above |
| `kubernetes_storage_class_v1.gp3` | Default StorageClass: encrypted `gp3` through `ebs.csi.aws.com` |
| `module.lbc_irsa`: `aws_iam_role`, `aws_iam_policy`, 1 policy attachment | `<project>-<env>-aws-load-balancer-controller` role and the official controller policy |
| `helm_release.aws_load_balancer_controller` | AWS Load Balancer Controller in `kube-system`, ServiceAccount annotated with the role ARN |
| `module.external_secrets_irsa`: `aws_iam_role`, `aws_iam_policy`, 1 policy attachment | `<project>-<env>-external-secrets` role, read-only on `<project>/<env>/*` secrets |
| `kubernetes_namespace_v1.external_secrets` | `external-secrets` namespace |
| `helm_release.external_secrets` | External Secrets Operator with CRDs, ServiceAccount annotated with the role ARN |
| `aws_eks_addon.metrics_server` | `metrics-server` managed add-on |

| Data source | Purpose |
| --- | --- |
| `aws_eks_cluster.this` | Finds the cluster by name: endpoint, CA, OIDC issuer and VPC ID |
| `aws_iam_openid_connect_provider.this` | Finds the cluster's IAM OIDC provider by issuer URL |
| `aws_partition.current`, `aws_caller_identity.current` | Build ARNs without hardcoding the partition or account ID |

All AWS resources are tagged through the provider `default_tags`: `Project`, `Env`, `Owner`, `ManagedBy` (`terraform`) and `Stack` (`addons`).

### Versions

| Component | Type | Version |
| --- | --- | --- |
| EBS CSI driver | EKS add-on | `v1.67.2-eksbuild.1` |
| AWS Load Balancer Controller | Helm chart `eks/aws-load-balancer-controller` | `3.6.2` (controller `v3.6.2`) |
| External Secrets Operator | Helm chart `external-secrets/external-secrets` | `2.14.0` (operator `v2.14.0`) |
| metrics-server | EKS add-on | `v0.9.0-eksbuild.14` |

Find newer versions with:

```bash
aws eks describe-addon-versions --kubernetes-version 1.37 --addon-name aws-ebs-csi-driver \
  --query 'addons[0].addonVersions[0:3].addonVersion'
helm search repo eks/aws-load-balancer-controller --versions | head -3
helm search repo external-secrets/external-secrets --versions | head -3
```

To upgrade the Load Balancer Controller, download `docs/install/iam_policy.json` from the matching controller tag into `policies/aws-load-balancer-controller-v<version>.json`, then change `lbc_chart_version`.

## Usage

Prerequisites: Terraform >= 1.11, the AWS CLI (used by the providers for `aws eks get-token`), the `eks` stack applied, and an active AWS SSO session (`aws sso login`).

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner
cp backend.hcl.example backend.hcl             # replace <account-id>

terraform init -backend-config=backend.hcl
terraform plan -out=tfplan                     # fails on the cluster lookup until eks is applied
terraform apply tfplan
```

From the repository root, `make up` applies `network`, `eks` and then this stack.

Check the result:

```bash
kubectl get storageclass                                  # gp3 (default)
kubectl -n kube-system get deploy aws-load-balancer-controller ebs-csi-controller metrics-server
kubectl -n external-secrets get pods
kubectl top nodes                                         # metrics-server is serving
```

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | (required) | AWS region, same as the `eks` stack |
| `owner` | (required) | Owner tag |
| `project` | `eks-platform` | Name prefix and `Project` tag |
| `env` | `dev` | Name part and `Env` tag |
| `ebs_csi_addon_version` | `v1.67.2-eksbuild.1` | `aws-ebs-csi-driver` add-on version |
| `lbc_chart_version` | `3.6.2` | AWS Load Balancer Controller chart version |
| `eso_chart_version` | `2.14.0` | External Secrets Operator chart version |
| `metrics_server_addon_version` | `v0.9.0-eksbuild.14` | `metrics-server` add-on version |

## Outputs

| Output | Description |
| --- | --- |
| `ebs_csi_role_arn` | IAM role of the EBS CSI controller |
| `lbc_role_arn` | IAM role of the AWS Load Balancer Controller |
| `external_secrets_role_arn` | IAM role of External Secrets Operator |
| `default_storage_class` | Name of the default StorageClass (`gp3`) |

## Cost and teardown

The stack itself adds no hourly cost: IAM roles, add-ons and controllers are free, and the pods run on the existing nodes. The cost comes from what the controllers create on request: an ALB or NLB per Ingress, Gateway or LoadBalancer Service (about $16/month each plus usage), and a `gp3` volume per PVC (about $0.08 per GB-month).

Those load balancers and volumes are created by controllers, not by Terraform, so Terraform cannot destroy them. Delete the Ingresses, LoadBalancer Services and PVCs (uninstall the apps) **before** destroying this stack, while the controllers are still running to clean up. `make down` enforces this: its `check-clean` step fails if any of them still exist, and only then destroys `addons`, `eks` and `network`.

```bash
make check-clean   # from the repository root: lists anything that would be orphaned
make down          # check-clean, then destroys addons, eks, network
```

`check-clean` uses a temporary kubeconfig for `eks-platform-dev` in the region from `AWS_REGION` or the active profile; override with `make down CLUSTER=<name> REGION=<region>`. PVCs are only checked while they exist: a PersistentVolume with a `Retain` reclaim policy keeps its EBS volume after the PVC is deleted.
