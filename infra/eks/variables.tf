variable "region" {
  description = "AWS region of the cluster (same as the network stack)."
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

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Keep it in standard support; extended support costs 6x more."
  type        = string
  default     = "1.37"
}

variable "node_instance_types" {
  description = "Instance types of the managed node group (amd64, see ADR 0006)."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Initial number of worker nodes. Ignored after creation, so an autoscaler can own it."
  type        = number
  default     = 2
}

variable "admin_permission_set_name" {
  description = "IAM Identity Center permission set whose role gets cluster-admin through an access entry."
  type        = string
  default     = "AdministratorAccess"
}
