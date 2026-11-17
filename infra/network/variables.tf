variable "region" {
  description = "AWS region."
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

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "One shared NAT Gateway instead of one per AZ (ADR 0007)."
  type        = bool
  default     = true
}
