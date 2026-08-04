provider "aws" {
  region = "us-west-2"
}

# Cluster connection for the kubernetes + helm providers, via EXPLICIT token auth.
#
# Why not in-cluster auth (empty `provider "kubernetes" {}`): that only works when the
# process runs in a pod whose container has KUBERNETES_SERVICE_HOST/PORT set and a mounted
# ServiceAccount token — the provider auto-detects in-cluster mode from those env vars. The
# env0 self-hosted agent spawns each deployment job as its own pod, and that pod does NOT
# surface those in-cluster signals to the tofu process, so the provider found no config and
# fell back to its default endpoint (http://localhost) — the "dial tcp [::1]:80: connection
# refused" error at kubernetes_namespace.{poc,app}.
#
# Token auth sidesteps that entirely: it does not depend on the env0 job pod's spec at all.
#   - data.aws_eks_cluster.this  -> the cluster's API endpoint + CA bundle (via eks:DescribeCluster).
#   - data.aws_eks_cluster_auth.this -> a short-lived bearer token minted FROM THE AWS PROVIDER'S
#     OWN CREDENTIALS (the env0 agent's EKS Pod Identity role) — the in-process equivalent of
#     `aws eks get-token`, so NO aws CLI and NO exec block are needed.
#
# PRINCIPAL NOTE (the crux): this token authenticates to Kubernetes as the AWS IAM role
# env0-agent-deploy-role (the Pod Identity role), NOT as the env0-deploy ServiceAccount. The
# cluster-admin RBAC for that IAM role is granted out-of-band by the agent/ stack's EKS access
# entry (agent/access_entry.tf) — the same principal the token authenticates as. (The SA's
# ClusterRoleBinding in agent/rbac.tf remains for Pod Identity/in-cluster tooling but is not
# what authorizes these provider calls.)
data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# helm provider v3: `kubernetes` is a nested OBJECT (`= { ... }`), and it has the SAME
# localhost fallback the kubernetes provider had — so it must be given the identical explicit
# connection, or helm_release.kube_state_metrics fails the same way after namespaces succeed.
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
