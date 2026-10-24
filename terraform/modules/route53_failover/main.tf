# --------------------------------------------------------------------------
# Hosted Zone en Route 53 (Opcional o Existente)
# --------------------------------------------------------------------------
resource "aws_route53_zone" "this" {
  count   = var.create_hosted_zone ? 1 : 0
  name    = var.domain_name
  comment = "Hosted Zone para Disaster Recovery Multi-Region (Warm Standby)"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-hosted-zone"
    }
  )
}

locals {
  zone_id   = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : var.existing_zone_id
  fqdn_name = "${var.record_subdomain}.${var.domain_name}"
}

# --------------------------------------------------------------------------
# Health Checks de Route 53 (Monitoreo cada 10 segundos para RTO < 15 min)
# --------------------------------------------------------------------------
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = var.health_check_path
  request_interval  = var.request_interval
  failure_threshold = var.failure_threshold

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-primary-hc-us-east-1"
      Role = "Primary"
    }
  )
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = var.secondary_alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = var.health_check_path
  request_interval  = var.request_interval
  failure_threshold = var.failure_threshold

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-secondary-hc-us-west-2"
      Role = "Secondary"
    }
  )
}

# --------------------------------------------------------------------------
# Registros DNS con Política de Enrutamiento Failover (PRIMARY / SECONDARY)
# --------------------------------------------------------------------------
resource "aws_route53_record" "primary" {
  zone_id         = local.zone_id
  name            = local.fqdn_name
  type            = "A"
  set_identifier  = "Primary-US-East-1"
  health_check_id = aws_route53_health_check.primary.id

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
  zone_id         = local.zone_id
  name            = local.fqdn_name
  type            = "A"
  set_identifier  = "Secondary-US-West-2"
  health_check_id = aws_route53_health_check.secondary.id

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }
}

