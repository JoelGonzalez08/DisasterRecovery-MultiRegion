output "bucket_id" {
  description = "ID del bucket S3"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN del bucket S3 (requerido para políticas IAM y CRR)"
  value       = aws_s3_bucket.this.arn
}

output "bucket_name" {
  description = "Nombre asignado al bucket S3"
  value       = aws_s3_bucket.this.bucket
}

output "replication_role_arn" {
  description = "ARN del rol IAM de replicación CRR (si está habilitado)"
  value       = try(aws_iam_role.replication[0].arn, null)
}
