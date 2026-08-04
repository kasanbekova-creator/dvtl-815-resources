provider "aws" {
  region = "us-west-2"
}

# Resolve the target cluster's API endpoint + CA so both providers can reach it.
data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}

# Both providers authenticate via exec auth (`aws eks get-token`) — the aws CLI must be
# on PATH (it is, in the env0 runner image and locally).
#
# NOTE THE INTENTIONAL ASYMMETRY between the two blocks below:
#   - kubernetes provider v3: `exec { ... }` is a nested BLOCK (no `=`).
#   - helm provider v3:       `kubernetes = { exec = { ... } }` are OBJECTS (with `=`).
# This is not a typo — the two providers' v3 schemas differ. Do not "normalize" them.

# --- kubernetes provider v3: exec is a BLOCK -------------------------------
provider "kubernetes" {
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name]
  }
}

# --- helm provider v3: kubernetes + exec are OBJECTS ------------------------
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.target.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name]
    }
  }
}
