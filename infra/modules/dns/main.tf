# infra/modules/dns
#
# Route 53 hosted zone (optional — see var.create_zone), 2 HTTPS health
# checks against /healthz/region (10s interval, failure threshold 3), and
# a PRIMARY/SECONDARY failover record set aliasing to each region's ALB.
# Per doc §7.3: theoretical failover floor is 30s (detection) + up to 60s
# (TTL) + client reconnect =~ 60-95s. This is a hard property of DNS-based
# failover, reported honestly rather than engineered away.

locals {
  common_tags = merge(var.tags, {
    "Project" = "rideflow"
    "Module"  = "dns"
  })

  zone_id = var.create_zone ? aws_route53_zone.this[0].zone_id : var.zone_id
}

resource "aws_route53_zone" "this" {
  count = var.create_zone ? 1 : 0
  name  = var.domain_name
  tags  = local.common_tags
}

# ---------------------------------------------------------------------------
# Health checks — one per region, 3 health-checker regions (doc §7.3)
# ---------------------------------------------------------------------------

resource "aws_route53_health_check" "primary" {
  count             = var.create_failover_records ? 1 : 0
  fqdn              = var.primary_alb_dns_name
  port              = var.health_check_port
  type              = "HTTPS"
  resource_path     = var.health_check_path
  request_interval  = var.health_check_interval
  failure_threshold = var.health_check_failure_threshold
  measure_latency   = true

  regions = [
    "us-east-1",
    "eu-west-1",
    "ap-southeast-2",
  ]

  tags = merge(local.common_tags, {
    Name = "rideflow-primary-region-health"
  })
}

resource "aws_route53_health_check" "secondary" {
  count             = var.create_failover_records ? 1 : 0
  fqdn              = var.secondary_alb_dns_name
  port              = var.health_check_port
  type              = "HTTPS"
  resource_path     = var.health_check_path
  request_interval  = var.health_check_interval
  failure_threshold = var.health_check_failure_threshold
  measure_latency   = true

  regions = [
    "us-east-1",
    "eu-west-1",
    "ap-southeast-2",
  ]

  tags = merge(local.common_tags, {
    Name = "rideflow-secondary-region-health"
  })
}

# ---------------------------------------------------------------------------
# Failover record set
# ---------------------------------------------------------------------------

resource "aws_route53_record" "primary" {
  count   = var.create_failover_records ? 1 : 0
  zone_id = local.zone_id
  name    = var.record_name
  type    = "A"

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary[0].id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  count   = var.create_failover_records ? 1 : 0
  zone_id = local.zone_id
  name    = var.record_name
  type    = "A"

  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary[0].id

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }
}
