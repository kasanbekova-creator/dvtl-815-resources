terraform {
  backend "s3" {
    bucket         = "natera-dvtl815-github-poc-state"
    key            = "agent/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "dvtl815-github-poc-locks"
    encrypt        = true

    # SAME dedicated github-poc bucket + lock table as the resources root (backend.tf) and the
    # dvtl-815-infra root, but a DISTINCT key (agent/terraform.tfstate) so this identity/RBAC stack
    # has its own independent state. Deliberately NOT the aws-poc fork's shared
    # `natera-dvtl815-poc-state` / `dvtl815-poc-locks`.
    #
    # The env0_agent IAM role this stack creates is scoped to read/write exactly this bucket + lock
    # table (iam.tf), so the deployment jobs the role backs can drive their OWN OpenTofu state in the
    # same bucket under different keys.
  }
}
