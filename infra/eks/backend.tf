terraform {
  # Settings come from backend.hcl (gitignored), because the bucket name contains the account ID.
  backend "s3" {}
}
