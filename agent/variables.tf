# Inputs for the env0-agent identity + RBAC stack.
#
# Every variable defaults to the fixed DVTL-815 github-poc constant, so this stack applies with no
# tfvars and no TF_VAR_* injection — it is a one-shot, hand-applied bootstrap, not a per-run
# workload. The defaults are the single source of truth for the account/region/cluster/namespace
# this fork's env0 agent runs against; override only if you are pointing the agent at a different
# environment.

variable "cluster_name" {
  description = <<-EOT
    Name of the existing EKS cluster (provisioned by eng/srep/eks-factory) the env0 self-hosted
    agent's deployment jobs run against. SHARED with the aws-poc fork — the `env0-` namespace
    prefixes elsewhere in this repo are what keep the two forks' workloads from colliding, and this
    stack's ServiceAccount lives in the agent's own `env0-agent` namespace for the same reason.
  EOT
  type        = string
  default     = "dvtl815-poc"
}

variable "account_id" {
  description = "AWS account ID the cluster and the env0_agent role live in. Used to build the DynamoDB lock-table ARN in iam.tf."
  type        = string
  default     = "355433853014"
}

variable "region" {
  description = "AWS region for the aws provider and for the ARNs (DynamoDB lock table) built in iam.tf."
  type        = string
  default     = "us-west-2"
}

variable "service_account_name" {
  description = <<-EOT
    Name of the Kubernetes ServiceAccount the env0 agent's deployment jobs run as. The Pod Identity
    association (pod_identity.tf) binds the env0_agent IAM role to THIS ServiceAccount in the agent
    namespace, and the cluster-admin ClusterRoleBinding (rbac.tf) grants it Kubernetes RBAC.
  EOT
  type        = string
  default     = "env0-deploy"
}

variable "agent_namespace" {
  description = <<-EOT
    Namespace the env0 self-hosted agent (and thus the env0-deploy ServiceAccount) runs in. Distinct
    from the workload namespaces (env0-poc-tfc-replacement, env0-dvtl815-app) so the agent's identity
    is isolated from the things it deploys.
  EOT
  type        = string
  default     = "env0-agent"
}

variable "state_bucket" {
  description = "S3 bucket holding OpenTofu state. The env0_agent role is scoped to list this bucket and read/write its objects (iam.tf); same bucket as this stack's own backend."
  type        = string
  default     = "natera-dvtl815-github-poc-state"
}

variable "lock_table" {
  description = "DynamoDB table for OpenTofu S3-backend state locking. The env0_agent role is scoped to Get/Put/DeleteItem on this table (iam.tf); same table as this stack's own backend."
  type        = string
  default     = "dvtl815-github-poc-locks"
}
