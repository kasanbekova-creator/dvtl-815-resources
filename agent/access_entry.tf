# EKS access entry granting the env0 agent's IAM role (iam.tf) cluster RBAC.
#
# THIS IS THE PRINCIPAL-MATCHING HALF OF THE FIX. The workload root's kubernetes/helm providers
# (../providers.tf) authenticate to dvtl815-poc with a token from data.aws_eks_cluster_auth, which
# is minted from the env0 agent's EKS Pod Identity credentials — so those providers authenticate to
# Kubernetes AS THE IAM ROLE env0-agent-deploy-role, not as the env0-deploy ServiceAccount.
#
# The cluster only grants Kubernetes RBAC to principals it knows about. The eks-factory cluster
# grants RBAC to SSO roles, not to our agent role, so without this entry the workload's providers
# authenticate with NO RBAC and every plan/apply fails `Unauthorized` (the classic next-step trap
# after connectivity is solved). This access entry + cluster-admin policy association gives the IAM
# role that RBAC.
#
# Why this is a SEPARATE grant from the ClusterRoleBinding in rbac.tf: that binding targets the
# env0-deploy ServiceAccount (the identity Pod Identity attaches AWS creds to, and the identity any
# in-cluster tooling would use). Token auth authenticates as the IAM ROLE instead — a DIFFERENT
# Kubernetes principal — so the SA binding does not authorize it. We grant BOTH: the SA binding
# keeps SA-based access working, and this access entry authorizes the token-auth path the providers
# actually use. Mirrors the proven aws-poc pipeline/eks_access.tf pattern (there the principal was
# the CodeBuild role; here it is the env0 Pod Identity role).
#
# Why it lives HERE (agent/) and not in the workload root: aws_eks_access_entry /
# aws_eks_access_policy_association are AWS control-plane resources (eks:CreateAccessEntry /
# eks:AssociateAccessPolicy) — they do NOT need the kubernetes/helm providers. Put in the workload
# root they create a bootstrap deadlock: the kube/helm providers must authenticate to the cluster to
# refresh state during `plan`, but the entry that grants that authentication would be created by the
# same plan — so `plan` dies `Unauthorized` before it can create the entry. This agent/ stack is
# applied BY HAND FIRST with an operator kubeconfig, so it creates the grant with no such deadlock;
# by the time env0 runs the workload, the role already has cluster-admin. (No `import {}` blocks on
# purpose: a standing import against a possibly-missing object silently falls back to CREATE.)
#
# Why CLUSTER-WIDE admin (AmazonEKSClusterAdminPolicy), not namespace-scoped: the workload CREATES
# namespaces (env0-poc-tfc-replacement, env0-dvtl815-app), and creating a namespace is a
# cluster-scoped operation — a namespace-scoped grant would fail `namespaces is forbidden ... at the
# cluster scope`. Same rationale as the ClusterRoleBinding in rbac.tf. (Trade-off: broad blast radius
# for the agent role; acceptable for a PoC. Tighten before production.)

resource "aws_eks_access_entry" "env0_agent" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.env0_agent.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "env0_agent_admin" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.env0_agent.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.env0_agent]
}
