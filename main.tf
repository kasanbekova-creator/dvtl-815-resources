# Dummy Kubernetes-layer resources for the DVTL-815 github-poc PoC. These exist only to make the
# kubernetes and helm providers do real work during an env0 plan/apply. Both are throwaways.
#
# NOTE: the one-time `import {}` blocks the old github-poc carried here (adopting a pre-existing
# namespace + kube-state-metrics release from an earlier partial apply) are GONE on purpose. Phase 1
# of the rebuild destroyed those objects, so this is a clean-slate create — there is nothing to
# import.

# (1) Throwaway namespace -----------------------------------------------------
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

# NOTE (DVTL-815): the EKS access entry that grants the deploy identity cluster access does NOT live
# here — on purpose. The kubernetes/helm providers must authenticate to the cluster to refresh state
# during `plan`; if the access entry granting that authentication were created by this same root, the
# first `plan` would fail `Unauthorized` (a bootstrap deadlock). For github-poc the env0 runner's own
# cluster access is granted out-of-band by the env0 IAM role's EKS access entry (external to this
# repo), so this workload root needs no access-entry resource.
