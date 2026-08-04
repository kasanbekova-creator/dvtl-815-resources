# env0 agent IAM role — the AWS identity the env0 self-hosted agent's deployment jobs assume when
# they run OpenTofu against this account. The role is delivered to the pods via EKS Pod Identity
# (pod_identity.tf), which is why the trust policy below trusts the Pod Identity service principal
# rather than EC2 or an OIDC provider.
#
# Style matches the aws-poc pipeline/iam.tf and the workload roots: trust + permissions expressed as
# aws_iam_policy_document data sources rather than inline jsonencode. Every permission statement is
# scoped to a specific ARN, or to "*" only for the actions AWS genuinely cannot scope
# (DescribeCluster, ACM request/list, Route53 change/lookup, ELBv2 Describe*).
#
# DVTL-815 note — what is DELIBERATELY ABSENT vs the aws-poc CodeBuild role: this role backs an
# in-cluster env0 agent, not a VPC-configured CodeBuild project driven by CodePipeline out of
# CodeCommit. So the CodeBuild-specific statements are dropped:
#   - CodeCommitRead: source arrives via git over the env0 agent, not codecommit:GitPull.
#   - CodeBuildVpcEni / CodeBuildEniPermission: the agent pod already has cluster-VPC networking;
#     it does not manage its own ENIs.
#   - CloudWatchLogs: job logs stream to env0, not to a /aws/codebuild log group.
#   - ArtifactBucket: no CodePipeline artifact hand-off; state lives in the S3 backend below.
#   - EksAccessEntry (eks:*AccessEntry* / AssociateAccessPolicy): the whole access-entry mechanism is
#     REPLACED here by a Kubernetes cluster-admin ClusterRoleBinding (rbac.tf), so the role needs no
#     eks: access-entry writes at all — only DescribeCluster.

# --- Trust policy: EKS Pod Identity assumes this role ------------------------
# NOT the usual EC2/IRSA trust. With EKS Pod Identity the EKS Auth service (principal
# pods.eks.amazonaws.com) assumes the role on the pod's behalf and hands it session credentials, so:
#   - the principal is the SERVICE pods.eks.amazonaws.com (no OIDC provider, no
#     aws:sub/aud conditions), and
#   - the trust MUST allow BOTH sts:AssumeRole AND sts:TagSession. Pod Identity attaches session
#     tags (cluster / namespace / service-account) when it assumes the role; omitting
#     sts:TagSession is a common mistake that makes every AssumeRole call fail and breaks the
#     association silently.
data "aws_iam_policy_document" "env0_agent_trust" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "env0_agent" {
  name               = "env0-agent-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.env0_agent_trust.json
}

# --- Permissions the env0 deployment jobs need -------------------------------
# Scoped exactly like aws-poc pipeline/iam.tf: the S3 bucket-vs-/* split, the DynamoDB table ARN,
# and "*" only where AWS forbids resource-level scoping. Kubernetes-side authorization is handled
# entirely by the cluster-admin ClusterRoleBinding (rbac.tf), so there are NO eks: access-entry
# actions here.
data "aws_iam_policy_document" "env0_agent" {
  # OpenTofu S3 backend: list the bucket, read/write/delete the state objects. Bucket-level actions
  # (ListBucket) take the bucket ARN; object-level actions take the bucket ARN + "/*". This is the
  # exact split aws-poc pipeline/iam.tf uses.
  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }
  statement {
    sid    = "StateObjectsReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${var.state_bucket}/*"]
  }

  # OpenTofu S3 backend DynamoDB lock — scoped to the specific lock table ARN.
  statement {
    sid    = "StateLockTable"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = ["arn:aws:dynamodb:${var.region}:${var.account_id}:table/${var.lock_table}"]
  }

  # EKS: the deployment jobs' kubernetes provider reads the cluster (DescribeCluster) to resolve its
  # endpoint + CA before authenticating. DescribeCluster takes no resource-level scoping and must be
  # "*". No eks:*AccessEntry* / AssociateAccessPolicy here — cluster RBAC is granted by the
  # ClusterRoleBinding in rbac.tf, not by an access entry.
  statement {
    sid       = "EksDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }

  # ACM for the app's wildcard cert (the workload's acm.tf): request the cert, poll it to ISSUED, tag
  # it, and delete it on teardown. ACM actions do not take a useful resource ARN here —
  # RequestCertificate has NO resource (the ARN does not exist yet) and ListCertificates is
  # account-wide — so this is "*". PoC breadth; tighten to the specific cert ARN via a condition
  # before production.
  statement {
    sid    = "AcmWildcardCertLifecycle"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DescribeCertificate",
      "acm:DeleteCertificate",
      "acm:ListCertificates",
      "acm:AddTagsToCertificate",
      "acm:ListTagsForCertificate",
      "acm:RemoveTagsFromCertificate",
    ]
    resources = ["*"]
  }

  # Route53 for ACM DNS-01 validation. ChangeResourceRecordSets / ListResourceRecordSets CAN be
  # scoped to the zone ARN; GetChange and the ListHostedZones* / GetHostedZone lookups do NOT support
  # resource-level scoping and MUST be "*". For this PoC everything is "*" to match aws-poc's breadth
  # (the zone id is discovered at apply time via the aws_route53_zone data source, so scoping the
  # change actions would require hardcoding arn:aws:route53:::hostedzone/<ZONEID> — do that when you
  # tighten).
  statement {
    sid    = "Route53CertValidation"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:GetChange",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:GetHostedZone",
      # The aws_route53_zone data source always reads the zone's tags, so the lookup needs this too
      # (ListTagsForResource takes no resource-level scoping — must be "*").
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # Read-only ELBv2 describes for a post-apply ALB health check (list the target groups the ALB
  # created for the app Ingress and check their target health). The AWS Load Balancer Controller that
  # makes the MUTATING ELB calls is the pre-existing one on the cluster (its own IRSA role), NOT this
  # role — so only Describe* is needed here. Describe* takes no resource scoping.
  statement {
    sid    = "AlbHealthCheckReadOnly"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "env0_agent" {
  name   = "env0-agent-deploy-policy"
  role   = aws_iam_role.env0_agent.id
  policy = data.aws_iam_policy_document.env0_agent.json
}
