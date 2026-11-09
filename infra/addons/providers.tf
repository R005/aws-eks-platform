provider "aws" {
  region = var.region # never hardcoded: comes from tfvars

  # Applied to every resource this provider creates.
  default_tags {
    tags = {
      Project   = var.project
      Env       = var.env
      Owner     = var.owner
      ManagedBy = "terraform"
      Stack     = "addons"
    }
  }
}

# Both Kubernetes providers authenticate with a short-lived token from `aws eks get-token`,
# fetched on every run with the caller's AWS credentials (AWS_PROFILE from the environment).
# No static token is written to state or to a kubeconfig file.

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
  }
}

# Helm provider 3.x: `kubernetes` and `exec` are attributes, not nested blocks.
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
    }
  }
}
