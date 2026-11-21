# GitLab CI reaches AWS with OIDC, so no access keys are stored anywhere (ADR 0016).

locals {
  gitlab_url      = "https://gitlab.com"
  gitlab_audience = "https://gitlab.com" # must match id_tokens aud in .gitlab-ci.yml
  cluster_name    = "${var.project}-${var.env}"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# AWS trusts the gitlab.com certificate chain directly, so no thumbprint is needed.
resource "aws_iam_openid_connect_provider" "gitlab" {
  url            = local.gitlab_url
  client_id_list = [local.gitlab_audience]
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gitlab.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "gitlab.com:aud"
      values   = [local.gitlab_audience]
    }

    # Exact match: only pipelines on main of this project. MR and other branch pipelines are refused.
    condition {
      test     = "StringEquals"
      variable = "gitlab.com:sub"
      values   = ["project_path:${var.gitlab_project_path}:ref_type:branch:ref:main"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = "${local.cluster_name}-gitlab-ci"
  description          = "GitLab CI on main: push the api image and deploy to ${local.cluster_name}"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ci" {
  # GetAuthorizationToken does not support resource-level permissions.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # BatchGetImage and DescribeImages let the push job see whether the tag already exists.
  statement {
    sid = "EcrPushApi"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.api.arn]
  }

  # Enough for aws eks update-kubeconfig. Kubernetes permissions come from the access entry (eks stack).
  statement {
    sid       = "EksDescribe"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${data.aws_partition.current.partition}:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}"]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "ecr-push-eks-describe"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}
