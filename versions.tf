terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    # aws feeds the kubernetes + helm providers their cluster connection: the endpoint + CA
    # (data.aws_eks_cluster) and a short-lived auth token minted from the agent's Pod Identity
    # credentials (data.aws_eks_cluster_auth). It also backs the workload's ACM/Route53 resources.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
