# Placeholder web app + internal ALB Ingress (DVTL-815 first real workload).
#
# Deployment + ClusterIP Service + Ingress. The pre-existing AWS Load Balancer Controller (see the
# Ingress note) turns the Ingress into an INTERNAL ALB. The image is a placeholder; swapping in the
# real app is a one-line change to var.app_image.

locals {
  labels = { app = var.app_name }
}

# --- Dedicated namespace for the app ----------------------------------------
# Separate from the throwaway poc-tfc-replacement (main.tf) so the app has its own lifecycle.
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "opentofu"
      "dvtl-815-poc"                 = "true"
      "purpose"                      = "web-app"
    }
  }

  # Goldilocks (a cluster-wide resource tool) stamps these two keys onto every namespace after
  # creation. Ignore ONLY these keys — not the whole maps — so we don't fight it on every apply while
  # still surfacing any other drift.
  lifecycle {
    ignore_changes = [
      metadata[0].annotations["goldilocks.fairwinds.com/vpa-resource-policy"],
      metadata[0].labels["goldilocks.fairwinds.com/vpa-update-mode"],
    ]
  }
}

# --- Deployment --------------------------------------------------------------
# Modest requests/limits, a notch above the kube-state-metrics release (this is a web server).
resource "kubernetes_deployment" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = var.app_replicas

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        container {
          name  = var.app_name
          image = "${var.app_image}:${var.app_image_tag}"

          # IfNotPresent is correct because tags are immutable git SHAs (ECR repo is IMMUTABLE): a
          # given tag is always the same bytes, so there is nothing to gain from re-pulling, and a
          # new deploy always carries a NEW tag (so it always pulls). Avoids the Always+:latest
          # nondeterminism the review flagged (Finding 4).
          image_pull_policy = "IfNotPresent"

          port {
            container_port = var.app_container_port
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          # Readiness gates traffic (only added to the ALB target group once it can serve); liveness
          # restarts a running-but-wedged pod. Both hit the app's dedicated /healthz endpoint (see
          # src/main.go in dvtl-815-app), so health is decoupled from the demo page at "/".
          readiness_probe {
            http_get {
              path = "/healthz"
              port = var.app_container_port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = var.app_container_port
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
        }
      }
    }
  }
}

# --- Service (ClusterIP) -----------------------------------------------------
# Plain ClusterIP: target-type=ip (below) routes the ALB directly to pod IPs, so the Service is only
# for selection/DNS — NOT a LoadBalancer. Name derived from var.app_name (one knob for "the app").
resource "kubernetes_service" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    type     = "ClusterIP"
    selector = local.labels

    # port (Service front, targeted by the Ingress backend) and target_port (container) are both
    # single-sourced from variables so front and backend cannot drift apart.
    port {
      port        = var.app_service_port
      target_port = var.app_container_port
      protocol    = "TCP"
    }
  }
}

# --- Ingress (internal ALB) --------------------------------------------------
# We CONSUME the pre-existing AWS Load Balancer Controller already on the cluster (its own Helm
# release + IRSA, in the aws-load-balancer-controller namespace) — this repo does not install one,
# does not declare the `alb` IngressClass, and needs no depends_on (the class is a pre-existing
# object referenced by name). Subnets are pinned explicitly to the routable internal-* subnets.
resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = "${var.app_name}-alb"
    namespace = kubernetes_namespace.app.metadata[0].name

    # Selects the external-dns-private controller (its --label-filter is external-dns-scope=private),
    # which writes the record into the account's PRIVATE <account-id>.natera.io zone. The public
    # controller ignores this Ingress. Reachability is governed by scheme=internal, not this label.
    labels = {
      "external-dns-scope" = "private"
    }

    annotations = {
      "alb.ingress.kubernetes.io/scheme"      = "internal"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/subnets"     = var.app_alb_subnet_ids

      # external-dns reads this and writes an A-alias for the ALB. Matches spec.rule[].host below.
      "external-dns.alpha.kubernetes.io/hostname" = var.app_hostname

      # HTTPS at the ALB, bound EXPLICITLY to our wildcard cert (acm.tf) — no auto-discovery.
      # We reference the *validation* resource's certificate_arn (not the raw cert): OpenTofu will
      # not create/update this Ingress until the cert is ISSUED, so the LBC never tries to attach a
      # not-yet-valid cert to the 443 listener. The ARN is already a string, so it drops straight
      # into this string-valued annotations map.
      "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate_validation.app.certificate_arn

      # cert ARN present + HTTPS:443 in listen-ports => the LBC provisions the 443 listener;
      # ssl-redirect sends :80 -> :443.
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect" = "443"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = var.app_hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.app.metadata[0].name
              port {
                number = var.app_service_port
              }
            }
          }
        }
      }
    }
  }
}
