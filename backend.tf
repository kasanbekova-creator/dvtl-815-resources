terraform {
  backend "s3" {
    bucket         = "natera-dvtl815-poc-state"
    key            = "resources/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "dvtl815-poc-locks"
    encrypt        = true

    # Same bucket as infra/, different key — separate state for this root module.
    #
    # Alternative (OpenTofu >= 1.10): drop dynamodb_table above and use S3-native locking:
    #   use_lockfile = true
  }
}
