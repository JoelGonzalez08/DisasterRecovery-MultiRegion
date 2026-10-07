output "alb_dns_name" {
  description = "DNS público del Application Load Balancer en us-east-1"
  value       = module.compute_alb_asg.alb_dns_name
}

output "alb_arn" {
  description = "ARN del Application Load Balancer"
  value       = module.compute_alb_asg.alb_arn
}

output "rds_endpoint" {
  description = "Endpoint de conexión de RDS MySQL (Escritor Multi-AZ)"
  value       = module.database_rds.db_endpoint
}

output "rds_arn" {
  description = "ARN de la base de datos primaria (para Read Replica en Fase 2)"
  value       = module.database_rds.db_instance_arn
}

output "s3_bucket_name" {
  description = "Nombre del bucket S3 origen"
  value       = module.storage_s3.bucket_name
}

output "s3_bucket_arn" {
  description = "ARN del bucket S3 origen (para regla CRR en Fase 2)"
  value       = module.storage_s3.bucket_arn
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB"
  value       = aws_dynamodb_table.user_sessions.name
}

output "dynamodb_table_arn" {
  description = "ARN de la tabla DynamoDB"
  value       = aws_dynamodb_table.user_sessions.arn
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group primario"
  value       = module.compute_alb_asg.asg_name
}

output "vpc_id" {
  description = "ID de la VPC primaria"
  value       = module.vpc.vpc_id
}
