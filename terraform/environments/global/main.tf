terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "global"
      ManagedBy   = "Terraform"
      Team        = "UTB-DR-Team"
    }
  }
}

# --------------------------------------------------------------------------
# Lectura de Estados Remotos (Primary us-east-1 y Secondary us-west-2)
# --------------------------------------------------------------------------
data "terraform_remote_state" "primary" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.primary_state_key
    region = var.aws_region
  }
}

data "terraform_remote_state" "secondary" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.secondary_state_key
    region = var.aws_region
  }
}

# --------------------------------------------------------------------------
# 1. Enrutamiento DNS con Failover Automático en Route 53 (Health Check 10s)
# --------------------------------------------------------------------------
module "route53_failover" {
  source = "../../modules/route53_failover"

  project_name       = var.project_name
  domain_name        = var.domain_name
  record_subdomain   = var.record_subdomain
  create_hosted_zone = var.create_hosted_zone
  existing_zone_id   = var.existing_zone_id

  primary_alb_dns_name   = data.terraform_remote_state.primary.outputs.alb_dns_name
  primary_alb_zone_id    = try(data.terraform_remote_state.primary.outputs.alb_zone_id, "Z35SXDOTRQ7X7K")
  secondary_alb_dns_name = data.terraform_remote_state.secondary.outputs.alb_dns_name
  secondary_alb_zone_id  = try(data.terraform_remote_state.secondary.outputs.alb_zone_id, "Z1H1FL5HABSF5")

  health_check_path = "/health"
  request_interval  = 10
  failure_threshold = 3
}

# --------------------------------------------------------------------------
# 2. Distribución Global AWS CloudFront con Origin Group Multi-Región
# --------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "dr_cdn" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "CloudFront Multi-Region Failover Distribution (us-east-1 -> us-west-2)"
  price_class     = "PriceClass_100"

  # Origen Primario: ALB en us-east-1
  origin {
    domain_name = data.terraform_remote_state.primary.outputs.alb_dns_name
    origin_id   = "primary-alb-us-east-1"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Origen Secundario (Warm Standby): ALB en us-west-2
  origin {
    domain_name = data.terraform_remote_state.secondary.outputs.alb_dns_name
    origin_id   = "secondary-alb-us-west-2"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Grupo de Orígenes con Conmutación por Error Automática (Origin Failover)
  origin_group {
    origin_id = "dr-multi-region-origin-group"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = "primary-alb-us-east-1"
    }

    member {
      origin_id = "secondary-alb-us-west-2"
    }
  }

  default_cache_behavior {
    target_origin_id       = "dr-multi-region-origin-group"
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Deshabilitar caché para endpoints dinámicos de auditoría y salud
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-cloudfront-dr"
  }
}

