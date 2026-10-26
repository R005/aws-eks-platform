output "state_bucket_name" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.tfstate.bucket
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the state."
  value       = aws_kms_key.tfstate.arn
}
