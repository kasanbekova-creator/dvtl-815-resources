variable "eks_cluster_name" {
  description = <<-EOT
    Name of the existing EKS cluster (provisioned by eng/srep/eks-factory) to deploy Kubernetes
    resources into. For pipeline runs this is injected via TF_VAR_eks_cluster_name from this
    repo's pipeline/ stack (CodeBuild project); the default below is only for local smoke-tests.
  EOT
  type        = string
  default     = "dvtl815-poc"
}

variable "namespace" {
  description = "Namespace created for the PoC and used by the kube-state-metrics release."
  type        = string
  default     = "poc-tfc-replacement"
}

# NOTE: var.codebuild_role_arn was removed here. The EKS access entry that consumed it moved to
# pipeline/eks_access.tf, which references the role locally (aws_iam_role.codebuild.arn) — so the
# workload no longer needs the ARN passed in via TF_VAR_codebuild_role_arn. See MIGRATION.md.

# --- Placeholder web app (app.tf) -------------------------------------------
# This workload CONSUMES the pre-existing AWS Load Balancer Controller, so there are no LBC
# chart/region/vpcId variables. Service and Ingress names are derived from app_name (one knob).

variable "app_namespace" {
  description = "Namespace for the placeholder web app."
  type        = string
  default     = "dvtl815-app"
}

variable "app_name" {
  description = "Name for the app Deployment, its pod label, Service, and (as <name>-alb) the Ingress."
  type        = string
  default     = "hello"
}

variable "app_image" {
  description = "Container image WITHOUT tag. The dvtl-815-app build pipeline owns this ECR repo and pushes SHA-tagged images to it; app_image_tag selects which one."
  type        = string
  default     = "355433853014.dkr.ecr.us-west-2.amazonaws.com/dvtl815-app"
}

variable "app_image_tag" {
  # The image tag is the app's git commit SHA, written into image_tag.auto.tfvars by the
  # dvtl-815-app build pipeline (commit-back hand-off) and picked up on the next plan/apply. This
  # is what RESOLVES review Finding 4: the tag is immutable (ECR repo is IMMUTABLE) and unique per
  # commit, so `tofu plan` shows a real app_image_tag diff and the manual approval promotes one
  # specific, traceable image into the cluster. The default below is only a bootstrap for a bare
  # local plan before the first pipeline build; auto.tfvars overrides it in the pipeline.
  description = "Immutable git-SHA tag of the app image to deploy. Set by dvtl-815-app via image_tag.auto.tfvars."
  type        = string
  default     = "bootstrap"
}

variable "app_container_port" {
  description = "Port the app container listens on (the Service's target_port follows this). 8080: the Go app runs as a non-root distroless user, which cannot bind ports <1024."
  type        = number
  default     = 8080
}

variable "app_service_port" {
  description = "Port the Service exposes and the Ingress backend targets. Stays 80 (the ALB fronts on 80->443); kept separate from app_container_port so the container port can change independently."
  type        = number
  default     = 80
}

variable "app_replicas" {
  description = "Number of app Deployment replicas."
  type        = number
  default     = 2
}

variable "app_alb_subnet_ids" {
  description = "Routable internal subnet IDs for app's internal ALB"
  type        = string
  default     = "subnet-06a15436cabfc17b2,subnet-0cbaa58a8949bf2b3,subnet-095d9900c9ab2b91f"
}

variable "app_hostname" {
  description = <<-EOT
    Friendly DNS hostname for the app, written to the account's PRIVATE Route53 zone by the
    cluster's external-dns-private controller (selected via the external-dns-scope=private label on
    the Ingress). Convention: <app>.<account-id>.natera.io. Resolves in-VPC and over VPN (TGW).
  EOT
  type        = string
  default     = "dvtl815.355433853014.natera.io"
}