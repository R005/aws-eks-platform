terraform {
  # Settings come from the gitignored backend.hcl, because the bucket name contains the account ID.
  backend "s3" {}
}
