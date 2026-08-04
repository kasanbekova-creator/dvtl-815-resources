# Wildcard ACM certificate for the app's internal ALB (DVTL-815).
#
# WHY THIS FILE EXISTS: the AWS Load Balancer Controller only brought up an HTTP:80 listener
# because the wildcard cert *.355433853014.natera.io did not exist, so its previous auto-discovery
# (cert-by-host-suffix) found nothing. We now ISSUE that cert here and bind it EXPLICITLY on the
# Ingress via alb.ingress.kubernetes.io/certificate-arn (see app.tf) instead of relying on
# auto-discovery — the binding is a hard resource reference, so the 443 listener is deterministic.
#
# The cert lives in THIS workload root on purpose: the Ingress consumes the ARN by direct resource
# reference (aws_acm_certificate_validation.app.certificate_arn), so there is no cross-state plumbing
# (no remote-state read, no TF_VAR passing). The identity that applies this root is the env0 deploy
# runner; its IAM policy (external to this repo — administered in env0/IAM) must grant the ACM +
# Route53 permissions this file needs on top of the EKS/kubernetes access.
#
# Region note: an ACM cert for an ALB must be in the ALB's region (us-west-2). The default aws
# provider (providers.tf) is us-west-2 — correct. (us-east-1 would only be for CloudFront.)

locals {
  # Parent DNS zone = app_hostname with its first label stripped.
  #   "dvtl815.355433853014.natera.io" -> "355433853014.natera.io"
  app_dns_zone_name = join(".", slice(split(".", var.app_hostname), 1, length(split(".", var.app_hostname))))

  # Wildcard cert covering every host in that zone (covers app_hostname and any siblings).
  app_cert_domain = "*.${local.app_dns_zone_name}"
}

# --- The PUBLIC hosted zone that anchors validation --------------------------
# Self-owned PUBLIC zone 355433853014.natera.io. DNS-01 validation records for the cert are written
# here; the pipeline IAM can write into this zone (confirmed). private_zone = false selects the
# public zone (an identically named private zone can also exist in the account — this disambiguates).
data "aws_route53_zone" "public" {
  name         = local.app_dns_zone_name
  private_zone = false
}

# --- The wildcard certificate ------------------------------------------------
# DNS validation (no email). create_before_destroy so a future domain/SAN change mints the
# replacement cert and rebinds the Ingress before the old cert is destroyed — no listener gap.
resource "aws_acm_certificate" "app" {
  domain_name       = local.app_cert_domain
  validation_method = "DNS"

  tags = {
    "dvtl-815-poc" = "true"
    "purpose"      = "app-alb-wildcard"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- DNS validation records --------------------------------------------------
# Standard robust pattern: for_each over domain_validation_options keyed by domain_name, so it is
# stable whether the cert carries 1 SAN (this case) or several. allow_overwrite = true so a stale
# validation record from a prior attempt is replaced rather than erroring. v6 attribute names:
# resource_record_name / resource_record_type / resource_record_value.
resource "aws_route53_record" "app_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.public.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# --- Gate: block until the cert is ISSUED ------------------------------------
# validation_record_fqdns wires an explicit dependency on the records above, so this resource is
# not attempted until they exist, and it then polls ACM until the cert reaches ISSUED. Anything
# referencing aws_acm_certificate_validation.app.certificate_arn (the Ingress) is therefore ordered
# strictly AFTER issuance. Uses the *validation* resource's certificate_arn, not the raw cert's,
# precisely to get that ordering.
#
# timeouts.create = 10m: a wildcard on a self-owned public zone (60s TTL) validates in minutes. The
# provider default is 75m, which would let a stuck validation hang the env0 deploy far longer than
# it should; 10m fails fast with a clear error instead.
resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for r in aws_route53_record.app_cert_validation : r.fqdn]

  timeouts {
    create = "10m"
  }
}
