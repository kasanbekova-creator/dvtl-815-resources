# EKS Pod Identity association — the delivery mechanism that hands the env0_agent IAM role
# (iam.tf) to pods running as the env0-deploy ServiceAccount in the agent namespace.
#
# This is the modern replacement for IRSA/OIDC: instead of annotating the ServiceAccount with a role
# ARN and wiring an OIDC provider, EKS Pod Identity binds (cluster, namespace, service_account) ->
# role_arn as a first-class control-plane association. The EKS Pod Identity Agent (a DaemonSet addon
# on the cluster) then injects credentials for that role into any pod using the ServiceAccount. That
# is why iam.tf's trust policy trusts the pods.eks.amazonaws.com service principal (with
# sts:AssumeRole + sts:TagSession), NOT an OIDC federated principal.
#
# The EKS Pod Identity Agent addon is confirmed installed and ACTIVE on the dvtl815-poc cluster, so
# this association takes effect as soon as it is created — no addon bootstrap is required from this
# stack.
#
# aws_eks_pod_identity_association is a real AWS provider resource (aws ~> 6.0). Its arguments are
# exactly cluster_name / namespace / service_account / role_arn — do NOT model this as a
# ServiceAccount annotation (that is the OLD IRSA approach; see rbac.tf, where the ServiceAccount is
# created WITHOUT an eks.amazonaws.com/role-arn annotation on purpose).
resource "aws_eks_pod_identity_association" "env0_agent" {
  cluster_name    = var.cluster_name
  namespace       = var.agent_namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.env0_agent.arn
}
