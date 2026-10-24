output "alb_dns_name" {
  description = "DNS público del Application Load Balancer en us-west-2 (Warm Standby)"
  value       = module.compute_alb_asg.alb_dns_name
}

output "alb_arn" {
  description = "ARN del Application Load Balancer secundario"
  value       = module.compute_alb_asg.alb_arn
}

output "alb_zone_id" {
  description = "Canonical Hosted Zone ID del ALB secundario (para Route 53 Alias en Fase 3)"
  value       = module.compute_alb_asg.alb_zone_id
}

output "rds_instance_id" {
  description = "ID de la instancia RDS Read Replica en us-west-2 (usado por failover_trigger.py)"
  value       = module.database_rds.db_instance_id
}

output "rds_endpoint" {
  description = "Endpoint de conexión de RDS MySQL Read Replica en us-west-2"
  value       = module.database_rds.db_endpoint
}

output "rds_arn" {
  description = "ARN de la Read Replica RDS en us-west-2"
  value       = module.database_rds.db_instance_arn
}

output "s3_replica_bucket_name" {
  description = "Nombre del bucket S3 réplica en us-west-2"
  value       = module.storage_s3.bucket_name
}

output "s3_replica_bucket_arn" {
  description = "ARN del bucket S3 réplica en us-west-2"
  value       = module.storage_s3.bucket_arn
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla global de DynamoDB"
  value       = data.terraform_remote_state.primary.outputs.dynamodb_table_name
}

output "dynamodb_replica_arn" {
  description = "ARN de la réplica de DynamoDB Global Table en us-west-2"
  value       = aws_dynamodb_table_replica.user_sessions.arn
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group secundario (escalado a 2 por failover_trigger.py)"
  value       = module.compute_alb_asg.asg_name
}

output "vpc_id" {
  description = "ID de la VPC secundaria en us-west-2"
  value       = module.vpc.vpc_id
}

