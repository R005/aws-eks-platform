output "ecr_repository_url" {
  description = "URL of the api ECR repository (<account-id>.dkr.ecr.<region>.amazonaws.com/<project>/api)."
  value       = aws_ecr_repository.api.repository_url
}

output "db_secret_name" {
  description = "Name of the Secrets Manager secret holding the database password (JSON key: password)."
  value       = aws_secretsmanager_secret.db.name
}

output "lab_zone_name_servers" {
  description = "The four Route 53 name servers to set as NS records for lab at the parent domain's DNS provider."
  value       = aws_route53_zone.lab.name_servers
}

output "lab_zone_name" {
  description = "Name of the delegated zone (lab.<domain>). make deploy builds the app host from it."
  value       = aws_route53_zone.lab.name
}
