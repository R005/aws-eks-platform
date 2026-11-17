variable "region" {
  description = "AWS region."
  type        = string
}

variable "project" {
  description = "Prefix for resource names."
  type        = string
  default     = "eks-platform"
}

variable "owner" {
  description = "Owner tag."
  type        = string
}
