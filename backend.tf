terraform {
  backend "s3" {
    bucket         = "natera-dvtl815-github-poc-state"
    key            = "resources/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "dvtl815-github-poc-locks"
    encrypt        = true

    # Same dedicated github-poc bucket as the infra root (created by dvtl-815-infra/bootstrap),
    # different key — separate state for this root module. Deliberately NOT the aws-poc fork's shared
    # `natera-dvtl815-poc-state` / `dvtl815-poc-locks`.
  }
}
