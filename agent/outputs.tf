# Handoff values for whoever wires up the env0 self-hosted agent after this stack is applied.

output "env0_agent_role_arn" {
  description = "ARN of the IAM role the env0 agent's deployment jobs assume (via EKS Pod Identity). Reference this when confirming the Pod Identity association or auditing the agent's AWS permissions."
  value       = aws_iam_role.env0_agent.arn
}

output "service_account_name" {
  description = "Name of the Kubernetes ServiceAccount the env0 deployment pods run as (in the agent namespace), bound to the AWS role above by Pod Identity and to cluster-admin by the ClusterRoleBinding."
  value       = kubernetes_service_account.env0_deploy.metadata[0].name
}
