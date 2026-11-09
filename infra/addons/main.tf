locals {
  name = "${var.project}-${var.env}" # eks-platform-dev, also the cluster name
}

# --- Cluster lookup -----------------------------------------------------------
# Found by name, so this stack does not read the eks stack's state.

data "aws_eks_cluster" "this" {
  name = local.name
}

# The IAM OIDC provider created by the eks stack, found by the cluster's issuer URL.
# Every IRSA trust policy in this stack federates through it (ADR 0005).
data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

locals {
  irsa_role_annotation = "eks.amazonaws.com/role-arn" # read by the EKS pod identity webhook
}

# --- EBS CSI driver -----------------------------------------------------------
# Provisions EBS volumes for PersistentVolumeClaims (the Postgres StatefulSet, ADR 0002).

locals {
  ebs_csi_service_account = "ebs-csi-controller-sa" # created by the add-on in kube-system
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8" # any 6.x from 6.8 on; the module source is not in the lock file, so pin it here

  name            = "${local.name}-ebs-csi"
  use_name_prefix = false
  description     = "EBS CSI driver controller (IRSA)"

  # AWS-managed policy, kept up to date by AWS as the driver gains features.
  policies = {
    AmazonEBSCSIDriverPolicy = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  oidc_providers = {
    this = {
      provider_arn               = data.aws_iam_openid_connect_provider.this.arn
      namespace_service_accounts = ["kube-system:${local.ebs_csi_service_account}"]
    }
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = data.aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_addon_version
  service_account_role_arn = module.ebs_csi_irsa.arn

  # Terraform is the source of truth: overwrite manual edits to add-on managed fields.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Default StorageClass: encrypted gp3. The gp2 class EKS creates uses the in-tree provisioner
# and is not marked default on current EKS versions, so this is the only default.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer" # create the volume in the AZ of the scheduled pod
  allow_volume_expansion = true

  parameters = {
    type                        = "gp3"
    encrypted                   = "true" # with the account's default aws/ebs KMS key
    "csi.storage.k8s.io/fstype" = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}

# --- AWS Load Balancer Controller ---------------------------------------------
# Creates ALBs and NLBs for Ingress, Gateway API and LoadBalancer Service objects.

locals {
  lbc_service_account = "aws-load-balancer-controller"
}

module "lbc_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "${local.name}-aws-load-balancer-controller"
  use_name_prefix = false
  description     = "AWS Load Balancer Controller (IRSA)"

  # The official policy published with this controller release (docs/install/iam_policy.json at
  # the matching tag), vendored so it changes only with the chart version. A missing file for a
  # new chart version fails the plan.
  policy_name             = "${local.name}-aws-load-balancer-controller"
  source_policy_documents = [file("${path.module}/policies/aws-load-balancer-controller-v${var.lbc_chart_version}.json")]

  oidc_providers = {
    this = {
      provider_arn               = data.aws_iam_openid_connect_provider.this.arn
      namespace_service_accounts = ["kube-system:${local.lbc_service_account}"]
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lbc_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = data.aws_eks_cluster.this.name
    # Set explicitly: IMDSv2 with a hop limit of 1 keeps pods from discovering them from instance metadata.
    region = var.region
    vpcId  = data.aws_eks_cluster.this.vpc_config[0].vpc_id

    serviceAccount = {
      create      = true
      name        = local.lbc_service_account
      annotations = { (local.irsa_role_annotation) = module.lbc_irsa.arn }
    }
  })]
}

# --- External Secrets Operator ------------------------------------------------
# Syncs AWS Secrets Manager secrets into Kubernetes Secrets (ADR 0004). The ClusterSecretStore
# is a custom resource, so it ships with the app deployment once these CRDs exist.

locals {
  eso_namespace       = "external-secrets"
  eso_service_account = "external-secrets"

  # Secrets Manager appends a random 6-character suffix to secret ARNs, so match on the name prefix.
  eso_secret_arn_pattern = "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/${var.env}/*"
}

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "${local.name}-external-secrets"
  use_name_prefix = false
  description     = "External Secrets Operator (IRSA)"

  # Custom statement instead of attach_external_secrets_policy, which also grants
  # secretsmanager:ListSecrets, BatchGetSecretValue and ssm:DescribeParameters on "*".
  policy_name = "${local.name}-external-secrets"
  permissions = {
    ReadEnvSecrets = {
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = [local.eso_secret_arn_pattern]
    }
  }

  oidc_providers = {
    this = {
      provider_arn               = data.aws_iam_openid_connect_provider.this.arn
      namespace_service_accounts = ["${local.eso_namespace}:${local.eso_service_account}"]
    }
  }
}

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = local.eso_namespace
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.eso_chart_version
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name

  values = [yamlencode({
    installCRDs = true

    serviceAccount = {
      create      = true
      name        = local.eso_service_account
      annotations = { (local.irsa_role_annotation) = module.external_secrets_irsa.arn }
    }
  })]

  # The controller's Service mutating webhook rejects new Services until its pods are ready.
  depends_on = [helm_release.aws_load_balancer_controller]
}

# --- metrics-server -----------------------------------------------------------
# Resource metrics API for kubectl top and the HorizontalPodAutoscaler. Published by EKS as a
# managed add-on, so AWS builds and patches it. It calls no AWS APIs, so it needs no IAM role.

resource "aws_eks_addon" "metrics_server" {
  cluster_name  = data.aws_eks_cluster.this.name
  addon_name    = "metrics-server"
  addon_version = var.metrics_server_addon_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # The add-on creates a Service; the Load Balancer Controller webhook must be ready first.
  depends_on = [helm_release.aws_load_balancer_controller]
}
