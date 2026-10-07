variable "aws_region" {
  description = "Región primaria de AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "dr-architecture"
}

variable "environment" {
  description = "Nombre del entorno"
  type        = string
  default     = "primary"
}

variable "db_username" {
  description = "Usuario administrador de RDS MySQL"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Contraseña de la base de datos RDS MySQL"
  type        = string
  sensitive   = true
  default     = "PasswordSeguraDR2026!"
}

variable "s3_bucket_prefix" {
  description = "Prefijo para el bucket S3 de comprobantes"
  type        = string
  default     = "dr-invoices-utb"
}
