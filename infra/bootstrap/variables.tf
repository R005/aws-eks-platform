variable "region" {
  description = "AWS region for the state bucket and KMS key."
  type        = string
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "eks-platform"
}

variable "owner" {
  description = "Team responsible for these resources (used in tags)."
  type        = string
}
