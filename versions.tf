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
    # aws is needed only for the data source that resolves the cluster endpoint + CA
    # that the kubernetes and helm providers authenticate against.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
