variable "region" {
  description = "AWS region for the VPC."
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

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread the subnets across."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "One shared NAT Gateway (true, lab) or one per AZ (false, production). See ADR 0007."
  type        = bool
  default     = true
}
