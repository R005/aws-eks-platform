variable "region" {
  description = "AWS region for the ECR repository and the secret (same as the cluster)."
  type        = string
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "eks-platform"
}

variable "env" {
  description = "Environment name, used in the secret name and tags."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Team responsible for these resources (used in tags)."
  type        = string
}

variable "ecr_keep_images" {
  description = "Number of most recent images kept in each ECR repository; older ones are expired."
  type        = number
  default     = 20
}

variable "db_password_version" {
  description = "Version of the generated database password. Increase it to generate and store a new password."
  type        = number
  default     = 1
}
