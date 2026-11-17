locals {
  name = "${var.project}-${var.env}"
}

# Found by tag, so this stack does not read the network stack's state.
data "aws_vpc" "this" {
  tags = {
    Name    = "${local.name}-vpc"
    Project = var.project
    Env     = var.env
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "EKS needs private subnets in at least two AZs. Is the network stack applied?"
    }
  }
}

# IAM Identity Center names the role AWSReservedSSO_<permission-set>_<random-suffix>.
data "aws_iam_roles" "sso_admin" {
  name_regex  = "^AWSReservedSSO_${var.admin_permission_set_name}_[0-9a-f]+$"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"

  lifecycle {
    postcondition {
      condition     = length(self.arns) == 1
      error_message = "Expected exactly one SSO role for permission set ${var.admin_permission_set_name}."
    }
  }
}

data "aws_partition" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29" # modules are not in the lock file, so pin here

  name               = local.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = data.aws_vpc.this.id
  subnet_ids = data.aws_subnets.private.ids

  # Public for kubectl from a laptop and CI runners, private for the nodes. Both need IAM auth.
  endpoint_public_access  = true
  endpoint_private_access = true

  # IAM OIDC provider for IRSA (ADR 0005).
  enable_irsa = true

  # Access entries only, no aws-auth ConfigMap (ADR 0013).
  authentication_mode = "API"

  # Off because it would create a second access entry for the same SSO role and fail the apply.
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    sso_admin = {
      principal_arn = one(data.aws_iam_roles.sso_admin.arns)

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  addons = {
    vpc-cni = {
      before_compute = true # nodes never become Ready without it
    }
    kube-proxy = {}
    coredns    = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD" # amd64 (ADR 0006)
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }
}
