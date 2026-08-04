# Kubernetes-side identity + authorization for the env0 agent's deployment jobs.
#
# Two halves of the same grant:
#   1. the ServiceAccount the pods run as (and that Pod Identity binds the AWS role to), and
#   2. the ClusterRoleBinding that gives that ServiceAccount its Kubernetes RBAC.
#
# This is the piece that REPLACES the aws-poc access-entry pattern (aws-poc pipeline/eks_access.tf,
# read as reference). There, cluster access was granted on the AWS side via an
# aws_eks_access_entry + AmazonEKSClusterAdminPolicy association. Here we grant it on the Kubernetes
# side via a native ClusterRoleBinding to the built-in cluster-admin ClusterRole — which is why
# iam.tf carries NO eks:*AccessEntry* / AssociateAccessPolicy actions.

# The namespace the env0 self-hosted agent (and its deployment-job ServiceAccount) live in.
#
# We create it HERE rather than relying on Helm's `--create-namespace` because this stack is
# applied FIRST (before the Helm install), and a ServiceAccount cannot be created in a namespace
# that does not yet exist — `tofu apply` would fail `namespaces "env0-agent" not found`. Owning
# the namespace in this stack makes the stack self-contained and correctly ordered.
#
# Consequence for the Helm step: DROP `--create-namespace` from the `helm install` (the namespace
# already exists), or Helm will error that it is already present.
resource "kubernetes_namespace_v1" "agent" {
  metadata {
    name = var.agent_namespace
  }
}

# The ServiceAccount the env0 deployment pods run as. Created WITHOUT any
# eks.amazonaws.com/role-arn annotation on purpose: the AWS role is delivered by the EKS Pod
# Identity association (pod_identity.tf), not by the old IRSA annotation mechanism.
#
# depends_on the namespace: the SA references the namespace only via a string var, so Terraform
# cannot infer the ordering from an attribute reference — the explicit dependency prevents the
# create-in-parallel race that would re-trigger `namespaces ... not found`.
resource "kubernetes_service_account" "env0_deploy" {
  metadata {
    name      = var.service_account_name
    namespace = var.agent_namespace
  }

  depends_on = [kubernetes_namespace_v1.agent]
}

# Bind the env0-deploy ServiceAccount to the built-in cluster-admin ClusterRole.
#
# Why CLUSTER-ADMIN (cluster-wide), not a namespace-scoped Role/RoleBinding: the deployment jobs
# CREATE namespaces (this fork's env0-poc-tfc-replacement, env0-dvtl815-app), and creating a
# namespace is a cluster-scoped operation. A namespace-scoped grant physically cannot authorize it —
# the job would fail `namespaces is forbidden ... at the cluster scope`. This is the same reasoning
# that made aws-poc use the cluster-wide AmazonEKSClusterAdminPolicy rather than a namespaced access
# scope. (Trade-off: broad blast radius for the agent's ServiceAccount; acceptable for a PoC.
# Tighten to an aggregated/custom ClusterRole before production.)
resource "kubernetes_cluster_role_binding" "env0_deploy_admin" {
  metadata {
    name = "env0-deploy-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.env0_deploy.metadata[0].name
    namespace = var.agent_namespace
  }

  depends_on = [kubernetes_namespace_v1.agent]
}
