variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "dr-architecture"
}

variable "environment" {
  description = "Entorno (primary, secondary)"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Lista de IDs de subredes privadas de datos (mínimo 2 en distintas AZs)"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security Group de las instancias EC2 autorizadas a conectar por el puerto 3306"
  type        = string
}

variable "instance_class" {
  description = "Tipo de instancia RDS (ej. db.t3.micro, db.t4g.micro)"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Capacidad de almacenamiento en GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Nombre de la base de datos MySQL (solo para la instancia primaria)"
  type        = string
  default     = "transactions_db"
}

variable "db_username" {
  description = "Usuario administrador maestro"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Contraseña maestra de la base de datos"
  type        = string
  sensitive   = true
  default     = "PasswordSeguraDR2026!"
}

variable "multi_az" {
  description = "Habilitar alta disponibilidad Multi-AZ en la región primaria"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Días de retención de backups automáticos (debe ser > 0 para permitir Read Replicas)"
  type        = number
  default     = 7
}

variable "is_read_replica" {
  description = "Indica si esta instancia es una Read Replica de otra región"
  type        = bool
  default     = false
}

variable "replicate_source_db" {
  description = "ARN del RDS primario cuando se despliega como Read Replica (Fase 2)"
  type        = string
  default     = null
}

variable "skip_final_snapshot" {
  description = "Omitir snapshot final al destruir (ideal para laboratorios universitarios)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Etiquetas comunes para los recursos"
  type        = map(string)
  default     = {}
}
