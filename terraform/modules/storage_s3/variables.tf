variable "bucket_name" {
  description = "Nombre globalmente único del bucket S3"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue (ej. primary, secondary)"
  type        = string
}

variable "enable_versioning" {
  description = "Habilitar versionado en el bucket (requisito estricto para S3 CRR)"
  type        = bool
  default     = true
}

variable "enable_force_destroy" {
  description = "Permitir eliminación forzada para pruebas y laboratorios académicos"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Etiquetas comunes para el bucket"
  type        = map(string)
  default     = {}
}
