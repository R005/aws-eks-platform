output "ebs_csi_role_arn" {
  description = "IRSA role of the EBS CSI controller."
  value       = module.ebs_csi_irsa.arn
}

output "default_storage_class" {
  description = "Default StorageClass."
  value       = kubernetes_storage_class_v1.gp3.metadata[0].name
}

output "lbc_role_arn" {
  description = "IRSA role of the AWS Load Balancer Controller."
  value       = module.lbc_irsa.arn
}

output "external_secrets_role_arn" {
  description = "IRSA role of External Secrets Operator, used by SecretStores without an auth block."
  value       = module.external_secrets_irsa.arn
}

output "external_dns_role_arn" {
  description = "IRSA role of ExternalDNS."
  value       = module.external_dns_irsa.arn
}
