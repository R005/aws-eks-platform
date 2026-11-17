variable "region" {
  description = "AWS region, the same as the network stack."
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

variable "kubernetes_version" {
  description = "Kubernetes version. Keep it in standard support; extended support costs 6x more."
  type        = string
  default     = "1.37"
}

variable "node_instance_types" {
  description = "Node instance types, amd64 (ADR 0006)."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_min_size" {
  description = "Minimum nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes."
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Initial nodes. Ignored after creation, so an autoscaler can own it."
  type        = number
  default     = 2
}

variable "admin_permission_set_name" {
  description = "IAM Identity Center permission set granted cluster-admin."
  type        = string
  default     = "AdministratorAccess"
}
