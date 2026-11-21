variable "region" {
  description = "AWS region, the same as the cluster."
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

variable "ecr_keep_images" {
  description = "Number of recent images ECR keeps."
  type        = number
  default     = 20
}

variable "db_password_version" {
  description = "Bump to generate and store a new database password."
  type        = number
  default     = 1
}

variable "domain_name" {
  description = "Parent domain; the zone is lab.<domain_name>. Set in terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name)) && !startswith(var.domain_name, "lab.")
    error_message = "domain_name must be a lowercase domain without a trailing dot or the lab. prefix, for example example.com."
  }
}

variable "gitlab_project_path" {
  description = "GitLab project (group/project) whose main branch may assume the CI role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$", var.gitlab_project_path))
    error_message = "gitlab_project_path must look like group/project."
  }
}
