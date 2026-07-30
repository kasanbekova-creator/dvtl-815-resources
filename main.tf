# Dummy Kubernetes-layer resources for the DVTL-815 PoC. These exist only to make the
# kubernetes and helm providers do real work during plan/apply. Both are throwaways.

# (1) Throwaway namespace -----------------------------------------------------
# One-time reconciliation (same situation as the helm_release import below): the namespace
# already exists on the cluster from an earlier partial apply but is missing from state, so a
# plain apply fails "namespaces ... already exists". This adopts it into state. The
# kubernetes_namespace import ID is just the namespace name (no slash — namespaces are
# cluster-scoped). No-op once imported; safe to leave in place.
import {
  to = kubernetes_namespace.poc
  id = "poc-tfc-replacement"
}

resource "kubernetes_namespace" "poc" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "opentofu"
      "dvtl-815-poc"                 = "true"
      "purpose"                      = "tfc-replacement"
    }
  }

  # Goldilocks (cluster resource tool) stamps these two keys after creation; ignore only these so we
  # don't fight it every apply. Same fix as kubernetes_namespace.app in app.tf.
  lifecycle {
    ignore_changes = [
      metadata[0].annotations["goldilocks.fairwinds.com/vpa-resource-policy"],
      metadata[0].labels["goldilocks.fairwinds.com/vpa-update-mode"],
    ]
  }
}

# (2) kube-state-metrics via Helm --------------------------------------------
# One-time reconciliation: a kube-state-metrics release already exists in the cluster (created
# by an earlier partial apply) but is missing from state, so a plain apply fails "cannot re-use
# a name that is still in use". This block adopts the existing release into state during the
# next plan/apply — it only records the release, it does not modify or recreate it on the
# cluster. The plan stage bakes the import into tfplan; the apply stage executes that saved
# plan. No-op once imported, so it is safe to leave in place. The helm provider import ID is
# "<namespace>/<release-name>".
import {
  to = helm_release.kube_state_metrics
  id = "poc-tfc-replacement/kube-state-metrics"
}

resource "helm_release" "kube_state_metrics" {
  name       = "kube-state-metrics"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  version    = "7.5.1"

  # Referencing the namespace resource creates an implicit dependency, so the namespace is
  # created first — no explicit depends_on needed.
  namespace        = kubernetes_namespace.poc.metadata[0].name
  create_namespace = false

  # Minimal values: single replica, small resource requests. In helm provider v3, `set` is
  # a LIST of objects (the v2 repeated `set {}` block form is gone).
  set = [
    {
      name  = "replicas"
      value = "1"
    },
    {
      name  = "resources.requests.cpu"
      value = "10m"
    },
    {
      name  = "resources.requests.memory"
      value = "32Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "50m"
    },
    {
      name  = "resources.limits.memory"
      value = "64Mi"
    }
  ]
}

# NOTE: the EKS access entry that grants this repo's CodeBuild role cluster access used to live here
# (old section 3). It moved to pipeline/eks_access.tf to break a bootstrap deadlock: the
# kubernetes/helm providers below must authenticate to the cluster to refresh state during `plan`,
# but the access entry granting that authentication was created by the same plan — so `plan` failed
# `Unauthorized` before it could create the entry. The entry is an AWS control-plane resource that
# never needed the kube/helm providers, so it now lives in the AWS-only pipeline/ stack (applied
# first). See MIGRATION.md.
