locals {
  name = "${var.project}-${var.env}" # eks-platform-dev
}

# --- Network lookup -----------------------------------------------------------
# Found by tag, so this stack does not read the network stack's state.

data "aws_vpc" "this" {
  tags = {
    Name    = "${local.name}-vpc"
    Project = var.project
    Env     = var.env
  }
}

# Nodes and the control plane ENIs go into the private subnets.
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

# --- Cluster admin role -------------------------------------------------------
# IAM Identity Center creates one role per permission set, named
# AWSReservedSSO_<permission-set>_<random-suffix>. Look it up, never hardcode it.

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

# --- EKS cluster --------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29" # any 21.x from 21.29 on; the module source is not in the lock file, so pin it here

  name               = local.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = data.aws_vpc.this.id
  subnet_ids = data.aws_subnets.private.ids

  # API endpoint reachable from the internet (kubectl from a laptop and CI runners),
  # and from inside the VPC for the nodes. Requests still need IAM authentication.
  endpoint_public_access  = true
  endpoint_private_access = true

  # Creates the IAM OIDC provider for IRSA (ADR 0005).
  enable_irsa = true

  # Access entries only: the aws-auth ConfigMap is not used.
  authentication_mode = "API"

  # Do not grant admin implicitly to whoever runs apply; the SSO role below is granted explicitly.
  # Both would create an access entry for the same role and the apply would fail.
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    sso_admin = {
      principal_arn = one(data.aws_iam_roles.sso_admin.arns) # path included; access entries accept it

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

  # EKS managed add-ons, at the latest version compatible with the cluster version.
  addons = {
    vpc-cni = {
      before_compute = true # must exist before nodes join, or they never become Ready
    }
    kube-proxy = {}
    coredns    = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD" # Amazon Linux 2023, amd64
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }
}
