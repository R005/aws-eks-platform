variable "region" {
  description = "AWS region, the same as the eks stack."
  type        = string
}

variable "project" {
  description = "Prefix for resource names."
  type        = string
  default     = "eks-platform"
}

variable "env" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner tag."
  type        = string
}

variable "ebs_csi_addon_version" {
  description = "aws-ebs-csi-driver add-on version."
  type        = string
  default     = "v1.67.2-eksbuild.1"
}

variable "lbc_chart_version" {
  description = "aws-load-balancer-controller chart version. Needs policies/aws-load-balancer-controller-v<version>.json."
  type        = string
  default     = "3.6.2"
}

variable "eso_chart_version" {
  description = "external-secrets chart version."
  type        = string
  default     = "2.14.0"
}

variable "metrics_server_addon_version" {
  description = "metrics-server add-on version."
  type        = string
  default     = "v0.9.0-eksbuild.14"
}

variable "external_dns_chart_version" {
  description = "external-dns chart version (kubernetes-sigs chart, not the app version)."
  type        = string
  default     = "1.23.0"
}

variable "domain_name" {
  description = "Parent domain; ExternalDNS manages lab.<domain_name> only. Set in terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name)) && !startswith(var.domain_name, "lab.")
    error_message = "domain_name must be a lowercase domain without a trailing dot or the lab. prefix, for example example.com."
  }
}
