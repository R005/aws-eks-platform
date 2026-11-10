variable "region" {
  description = "AWS region of the cluster (same as the eks stack)."
  type        = string
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "eks-platform"
}

variable "env" {
  description = "Environment name, used in resource names and tags."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Team responsible for these resources (used in tags)."
  type        = string
}

variable "ebs_csi_addon_version" {
  description = "Version of the aws-ebs-csi-driver EKS add-on (aws eks describe-addon-versions --addon-name aws-ebs-csi-driver)."
  type        = string
  default     = "v1.67.2-eksbuild.1"
}

variable "lbc_chart_version" {
  description = "aws-load-balancer-controller chart version (same as the controller version). Needs policies/aws-load-balancer-controller-v<version>.json."
  type        = string
  default     = "3.6.2"
}

variable "eso_chart_version" {
  description = "external-secrets chart version (same as the operator version)."
  type        = string
  default     = "2.14.0"
}

variable "metrics_server_addon_version" {
  description = "Version of the metrics-server EKS add-on (aws eks describe-addon-versions --addon-name metrics-server)."
  type        = string
  default     = "v0.9.0-eksbuild.14"
}

variable "external_dns_chart_version" {
  description = "external-dns chart version (kubernetes-sigs chart; the app version differs, for example chart 1.23.0 ships ExternalDNS 0.23.0)."
  type        = string
  default     = "1.23.0"
}

variable "domain_name" {
  description = "Parent domain (for example example.com). ExternalDNS manages records in lab.<domain_name> only. Set it in terraform.tfvars; never commit it."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name)) && !startswith(var.domain_name, "lab.")
    error_message = "domain_name must be a lowercase domain without a trailing dot or the lab. prefix, for example example.com."
  }
}
