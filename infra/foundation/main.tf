# Resources that outlive the cluster. Applied once, not part of make up / make down.

resource "aws_ecr_repository" "api" {
  name = "${var.project}/api"

  # A pushed Git SHA tag can never be overwritten.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # A customer-managed KMS key adds nothing for app images.
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
        tagStatus   = "any" # includes untagged, such as replaced attestation manifests
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_keep_images
      }
      action = { type = "expire" }
    }]
  })
}

# Read by External Secrets Operator, whose IRSA role may read <project>/<env>/* (addons stack).
resource "aws_secretsmanager_secret" "db" {
  name        = "${var.project}/${var.env}/db"
  description = "PostgreSQL password for the task tracker (${var.env})"

  recovery_window_in_days = 7 # lab value; the default is 30
}

# Ephemeral: never stored in plan or state.
ephemeral "random_password" "db" {
  length           = 32
  special          = true
  override_special = "-_.+=" # no quotes, slashes or shell metacharacters
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  # Write-only, and only sent when the version changes: later runs generate a password that is
  # discarded until db_password_version is bumped.
  secret_string_wo         = jsonencode({ password = ephemeral.random_password.db.result })
  secret_string_wo_version = var.db_password_version
}

# lab.<domain> (ADR 0010), delegated from the parent domain. Kept between sessions, because a
# recreated zone gets new name servers and the delegation would have to be redone.
resource "aws_route53_zone" "lab" {
  name    = "lab.${var.domain_name}"
  comment = "Delegated subdomain for ${var.project} app hostnames"

  # force_destroy stays false, so records written by ExternalDNS are never deleted by accident.
  # Removing the zone on purpose means deleting this block first, as a reviewed change.
  lifecycle {
    prevent_destroy = true
  }
}

# Covers lab.<domain> and *.lab.<domain>. The AWS Load Balancer Controller finds it by the Ingress
# host, so the ARN is never passed around (ADR 0014). It must be in the cluster's region.
resource "aws_acm_certificate" "lab" {
  domain_name               = aws_route53_zone.lab.name
  subject_alternative_names = ["*.${aws_route53_zone.lab.name}"]
  validation_method         = "DNS"

  # A replacement is issued before the old one is deleted, so a listener using it never blocks.
  lifecycle {
    create_before_destroy = true
  }
}

# The apex and the wildcard need the same CNAME, so the second write must overwrite the first.
# ACM keeps using these records for renewal.
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

# Waits until the certificate is ISSUED; fails after 75 minutes if the delegation does not resolve.
resource "aws_acm_certificate_validation" "lab" {
  certificate_arn         = aws_acm_certificate.lab.arn
  validation_record_fqdns = [for record in aws_route53_record.lab_cert_validation : record.fqdn]
}
