output "state_bucket_name" {
  description = "Terraform state bucket."
  value       = aws_s3_bucket.tfstate.bucket
}

output "kms_key_arn" {
  description = "KMS key that encrypts the state."
  value       = aws_kms_key.tfstate.arn
}
