output "db_instance_id" {
  description = "ID del recurso RDS"
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "ARN de la instancia RDS (necesario para configurar Read Replica en Fase 2)"
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "Endpoint completo de conexión a MySQL (host:puerto)"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "Dirección de host (DNS) de la base de datos"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Puerto de escucha del servicio MySQL"
  value       = aws_db_instance.this.port
}

output "db_security_group_id" {
  description = "ID del Security Group asociado a RDS"
  value       = aws_security_group.rds.id
}
