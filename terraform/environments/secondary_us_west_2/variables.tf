variable "aws_region" {
  description = "Región secundaria de AWS (Warm Standby)"
  type        = string
  default     = "us-west-2"
}

variable "primary_aws_region" {
  description = "Región primaria de AWS donde reside el estado y recursos origen"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "dr-architecture"
}

variable "environment" {
  description = "Nombre del entorno secundario"
  type        = string
  default     = "secondary"
}

variable "state_bucket" {
  description = "Bucket S3 donde se almacena el estado remoto de Terraform"
  type        = string
  default     = "dr-proyecto-terraform-state-utb"
}

variable "primary_state_key" {
  description = "Ruta del archivo tfstate del entorno primario"
  type        = string
  default     = "primary/terraform.tfstate"
}

variable "db_username" {
  description = "Usuario administrador de RDS MySQL (usado por la API tras promoción)"
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
  description = "Prefijo para el bucket S3 réplica de comprobantes en us-west-2"
  type        = string
  default     = "dr-invoices-utb-replica"
}

