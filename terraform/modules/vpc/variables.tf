variable "project_name" {
  description = "Nombre del proyecto para prefijos de recursos"
  type        = string
  default     = "dr-architecture"
}

variable "environment" {
  description = "Entorno de despliegue (ej. primary, secondary)"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Lista de 2 CIDRs para subredes públicas (ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Lista de 2 CIDRs para subredes privadas de aplicación (EC2 ASG)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "Lista de 2 CIDRs para subredes privadas de datos (RDS MySQL)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "tags" {
  description = "Etiquetas comunes para los recursos"
  type        = map(string)
  default     = {}
}
