provider "aws" {
  region = var.region
}

# Resolve the target cluster's API endpoint + CA bundle so the kubernetes provider below has
# something to authenticate against. eks:DescribeCluster (which this read performs) is granted to
# the operator's own admin credentials, not to the env0_agent role this stack creates.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# IMPORTANT — read before "fixing" this to match the repo-root providers.tf:
#
# This stack is applied BY HAND by an operator running `tofu apply` locally with an admin
# kubeconfig. It is NOT the workload, and it does NOT run on the env0 agent pod. So it authenticates
# to the cluster the way that operator would from their laptop: exec auth that shells out to
# `aws eks get-token` for the cluster, using the endpoint + CA from the data source above. That is
# the CORRECT and intentional style HERE.
#
# The repo-root ../providers.tf deliberately uses the OPPOSITE approach (bare in-cluster auth, no
# host / CA / exec) because the workload root DOES run as a pod on the cluster and picks up the
# pod's mounted ServiceAccount token automatically. Do NOT copy that in-cluster style into this
# file — this stack has no pod-mounted token to read, and bootstrapping the very RBAC that would
# grant one is precisely this stack's job.
#
# kubernetes provider v3: `exec` is a nested BLOCK (`exec { ... }`, no `=`), not an `= { ... }`
# object — the v3 schema rejects the object/assignment form.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.cluster_name,
      "--region",
      var.region,
    ]
  }
}
