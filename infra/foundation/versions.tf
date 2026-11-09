terraform {
  # 1.11+ is needed for S3 native state locking (use_lockfile) and for write-only attributes.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x, never 7.x; the exact version is pinned in .terraform.lock.hcl
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7" # 3.7+ has the ephemeral random_password resource
    }
  }
}
