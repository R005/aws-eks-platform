provider "aws" {
  region = var.region # never hardcoded: comes from tfvars

  # Applied to every resource this provider creates.
  default_tags {
    tags = {
      Project   = var.project
      Env       = var.env
      Owner     = var.owner
      ManagedBy = "terraform"
      Stack     = "network"
    }
  }
}
