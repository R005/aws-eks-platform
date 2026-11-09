output "ebs_csi_role_arn" {
  description = "IAM role assumed by the EBS CSI controller through IRSA."
  value       = module.ebs_csi_irsa.arn
}

output "default_storage_class" {
  description = "Name of the default StorageClass."
  value       = kubernetes_storage_class_v1.gp3.metadata[0].name
}

output "lbc_role_arn" {
  description = "IAM role assumed by the AWS Load Balancer Controller through IRSA."
  value       = module.lbc_irsa.arn
}

output "external_secrets_role_arn" {
  description = "IAM role assumed by External Secrets Operator through IRSA. Referenced by the ClusterSecretStore."
  value       = module.external_secrets_irsa.arn
}
