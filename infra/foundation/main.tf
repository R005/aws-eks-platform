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

# --- DNS ----------------------------------------------------------------------
# Public zone for lab.<domain> (ADR 0010). The parent domain delegates to it with NS records
# set once at its DNS provider. Kept between sessions: a recreated zone gets new name servers,
# which means redoing the delegation and waiting for propagation.

resource "aws_route53_zone" "lab" {
  name    = "lab.${var.domain_name}"
  comment = "Delegated subdomain for ${var.project} app hostnames"

  # force_destroy is left false: a destroy fails while the zone still holds records
  # (for example ones written by ExternalDNS), so they are never deleted by accident.

  # Terraform refuses any plan that destroys the zone, including a full terraform destroy of this
  # stack. Removing the zone on purpose means deleting this block first, as a reviewed change.
  lifecycle {
    prevent_destroy = true
  }
}

# --- TLS certificate ----------------------------------------------------------
# One ACM certificate for lab.<domain> and *.lab.<domain>, used by the ALB (ADR 0014). The AWS Load
# Balancer Controller finds it by the Ingress host, so its ARN is never passed around. Same region
# as the cluster: an ALB can only use certificates from its own region.

resource "aws_acm_certificate" "lab" {
  domain_name               = aws_route53_zone.lab.name
  subject_alternative_names = ["*.${aws_route53_zone.lab.name}"]
  validation_method         = "DNS"

  # Any replacement (for example a new SAN) issues the new certificate before the old one is
  # deleted, so a listener that still uses the old one never blocks the change.
  lifecycle {
    create_before_destroy = true
  }
}

# ACM asks for one CNAME per name. The apex and the wildcard get the same record, so both
# instances write the same CNAME; allow_overwrite lets the second one succeed instead of
# failing with "already exists". ACM keeps using the records for automatic renewal.
resource "aws_route53_record" "lab_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.lab.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.lab.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

# Not a real AWS object: it waits during apply until ACM reports the certificate as ISSUED
# (usually a few minutes; it fails after 75 minutes if the delegation does not resolve).
resource "aws_acm_certificate_validation" "lab" {
  certificate_arn         = aws_acm_certificate.lab.arn
  validation_record_fqdns = [for record in aws_route53_record.lab_cert_validation : record.fqdn]
}
