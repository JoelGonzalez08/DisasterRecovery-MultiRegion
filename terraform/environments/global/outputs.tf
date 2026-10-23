output "cloudfront_domain_name" {
  description = "Dominio global de CloudFront con Origin Failover hacia us-east-1 y us-west-2"
  value       = aws_cloudfront_distribution.dr_cdn.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID de la distribución de CloudFront"
  value       = aws_cloudfront_distribution.dr_cdn.id
}

output "route53_failover_fqdn" {
  description = "FQDN del registro DNS con política Failover en Route 53"
  value       = module.route53_failover.failover_fqdn
}

output "route53_hosted_zone_id" {
  description = "ID de la Hosted Zone en Route 53"
  value       = module.route53_failover.hosted_zone_id
}

output "route53_name_servers" {
  description = "Servidores de nombres autoritativos para probar resolución DNS Failover con dig/nslookup"
  value       = module.route53_failover.name_servers
}

output "primary_health_check_id" {
  description = "ID del Health Check primario en Route 53"
  value       = module.route53_failover.primary_health_check_id
}

output "secondary_health_check_id" {
  description = "ID del Health Check secundario en Route 53"
  value       = module.route53_failover.secondary_health_check_id
}

