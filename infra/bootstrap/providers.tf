provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Env       = "shared" # state storage serves every environment
      Owner     = var.owner
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
