terraform {
  # 1.11+ is needed for S3 native state locking (use_lockfile).
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x, never 7.x; the exact version is pinned in .terraform.lock.hcl
    }
  }
}
