# Persistent resources that outlive the cluster: the image registry and the app secrets.
# Not part of make up / make down, like bootstrap.

# --- ECR ----------------------------------------------------------------------

resource "aws_ecr_repository" "api" {
  name = "${var.project}/api"

  # A tag always points at the same image: a pushed Git SHA can never be overwritten.
  image_tag_mutability = "IMMUTABLE"

  # Basic scanning for OS package CVEs on every push.
  image_scanning_configuration {
    scan_on_push = true
  }

  # AES256 (S3-managed keys) is the default; a customer-managed KMS key is not needed for app images.
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last ${var.ecr_keep_images} images"
      selection = {
        tagStatus   = "any" # tagged and untagged (for example, replaced attestation manifests)
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_keep_images
      }
      action = { type = "expire" }
    }]
  })
}

# --- Database secret ----------------------------------------------------------
# Read by External Secrets Operator, whose IRSA role may read <project>/<env>/* (addons stack).

resource "aws_secretsmanager_secret" "db" {
  name        = "${var.project}/${var.env}/db"
  description = "PostgreSQL password for the task tracker (${var.env})"

  recovery_window_in_days = 7 # lab value; the default is 30
}

# Generated on every plan/apply but never stored in plan or state (ephemeral resource).
ephemeral "random_password" "db" {
  length           = 32
  special          = true
  override_special = "-_.+=" # no quotes, slashes or shell metacharacters
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  # Write-only: sent to AWS, never persisted in state. Only written when the version changes,
  # so the password generated on later runs is discarded until db_password_version is bumped.
  secret_string_wo         = jsonencode({ password = ephemeral.random_password.db.result })
  secret_string_wo_version = var.db_password_version
}
