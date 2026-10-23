variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "dr-architecture"
}

variable "domain_name" {
  description = "Dominio base en Route 53 para el enrutamiento global DR"
  type        = string
  default     = "dr-utb-cloud.com"
}

variable "record_subdomain" {
  description = "Subdominio del endpoint transaccional (ej. api.dr-utb-cloud.com)"
  type        = string
  default     = "api"
}

variable "create_hosted_zone" {
  description = "Indica si se debe crear una nueva Hosted Zone pública en Route 53"
  type        = bool
  default     = true
}

variable "existing_zone_id" {
  description = "ID de una Hosted Zone existente cuando create_hosted_zone es false"
  type        = string
  default     = null
}

variable "primary_alb_dns_name" {
  description = "DNS público del ALB primario en us-east-1"
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Canonical Hosted Zone ID del ALB primario en us-east-1"
  type        = string
}

variable "secondary_alb_dns_name" {
  description = "DNS público del ALB secundario en us-west-2 (Warm Standby)"
  type        = string
}

variable "secondary_alb_zone_id" {
  description = "Canonical Hosted Zone ID del ALB secundario en us-west-2"
  type        = string
}

variable "health_check_path" {
  description = "Ruta HTTP para los Health Checks de Route 53"
  type        = string
  default     = "/health"
}

variable "request_interval" {
  description = "Intervalo en segundos entre Health Checks de Route 53 (10 o 30)"
  type        = number
  default     = 10
}

variable "failure_threshold" {
  description = "Número de fallos consecutivos para declarar la región como no saludable"
  type        = number
  default     = 3
}

variable "tags" {
  description = "Etiquetas comunes para los recursos de Route 53"
  type        = map(string)
  default     = {}
}

