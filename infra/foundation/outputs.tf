output "ecr_repository_url" {
  description = "URL of the api ECR repository (<account-id>.dkr.ecr.<region>.amazonaws.com/<project>/api)."
  value       = aws_ecr_repository.api.repository_url
}

output "db_secret_name" {
  description = "Name of the Secrets Manager secret holding the database password (JSON key: password)."
  value       = aws_secretsmanager_secret.db.name
}
