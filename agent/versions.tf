# Version pins for the env0-agent identity + RBAC stack.
#
# This stack provisions the IAM role, EKS Pod Identity association, ServiceAccount, and
# cluster-admin ClusterRoleBinding that the env0 self-hosted agent's deployment jobs need on the
# shared EKS cluster dvtl815-poc. It is applied BY HAND by an operator with an admin kubeconfig,
# NOT by the agent itself and NOT as part of a workload run (see providers.tf for why the
# kubernetes provider uses exec auth here rather than the in-cluster style the workload root uses).
#
# No helm provider: unlike the workload root, this stack installs no charts — it only creates a
# ServiceAccount and a ClusterRoleBinding (kubernetes provider) plus AWS-side identity (aws provider).

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
