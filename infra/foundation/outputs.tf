output "ecr_repository_url" {
  description = "api ECR repository URL."
  value       = aws_ecr_repository.api.repository_url
}

output "db_secret_name" {
  description = "Secrets Manager secret with the database password (JSON key password)."
  value       = aws_secretsmanager_secret.db.name
}

output "lab_zone_name_servers" {
  description = "Name servers to set as NS records for lab at the parent domain."
  value       = aws_route53_zone.lab.name_servers
}

output "lab_zone_name" {
  description = "Delegated zone name (lab.<domain>), used by make deploy for the app host."
  value       = aws_route53_zone.lab.name
}
