provider "aws" {
  region = var.region # never hardcoded: comes from tfvars

  # Applied to every resource this provider creates.
  default_tags {
    tags = {
      Project   = var.project
      Env       = "shared" # state storage serves all environments
      Owner     = var.owner
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
