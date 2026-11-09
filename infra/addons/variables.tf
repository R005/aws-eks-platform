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
