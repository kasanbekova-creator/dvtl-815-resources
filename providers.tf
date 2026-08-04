provider "aws" {
  region = "us-west-2"
}

# The env0 self-hosted agent runs deployment jobs as a pod on cluster dvtl815-poc.
# Because the pod runs on the cluster itself, the kubernetes and helm providers
# automatically pick up in-cluster auth: they read the pod's mounted ServiceAccount
# token and CA bundle, and use the KUBERNETES_SERVICE_HOST env var injected by
# Kubernetes — no host, cluster_ca_certificate, or exec block is needed.
#
# Kubernetes RBAC for the ServiceAccount (env0-deploy) is granted out-of-band by
# the separate agent/ stack via a cluster-admin ClusterRoleBinding.

provider "kubernetes" {}

provider "helm" {
  kubernetes = {}
}
