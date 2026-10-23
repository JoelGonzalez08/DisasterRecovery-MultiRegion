output "hosted_zone_id" {
  description = "ID de la Hosted Zone en Route 53"
  value       = local.zone_id
}

output "name_servers" {
  description = "Servidores de nombres asignados a la Hosted Zone en Route 53"
  value       = var.create_hosted_zone ? aws_route53_zone.this[0].name_servers : []
}

output "failover_fqdn" {
  description = "FQDN del registro DNS con política Failover"
  value       = aws_route53_record.primary.fqdn
}

output "primary_health_check_id" {
  description = "ID del Health Check de Route 53 para la región primaria (us-east-1)"
  value       = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  description = "ID del Health Check de Route 53 para la región secundaria (us-west-2)"
  value       = aws_route53_health_check.secondary.id
}

