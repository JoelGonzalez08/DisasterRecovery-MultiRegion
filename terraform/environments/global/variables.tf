variable "aws_region" {
  description = "Región de operación para servicios globales de AWS (Route 53 y CloudFront operan desde us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "dr-architecture"
}

variable "state_bucket" {
  description = "Bucket S3 donde se almacena el estado remoto de Terraform"
  type        = string
  default     = "dr-proyecto-terraform-state-utb"
}

variable "primary_state_key" {
  description = "Ruta del archivo tfstate del entorno primario (us-east-1)"
  type        = string
  default     = "primary/terraform.tfstate"
}

variable "secondary_state_key" {
  description = "Ruta del archivo tfstate del entorno secundario (us-west-2)"
  type        = string
  default     = "secondary/terraform.tfstate"
}

variable "domain_name" {
  description = "Dominio base para Route 53 Failover DNS"
  type        = string
  default     = "dr-utb-cloud.com"
}

variable "record_subdomain" {
  description = "Subdominio del servicio API"
  type        = string
  default     = "api"
}

variable "create_hosted_zone" {
  description = "Indica si se debe crear la Hosted Zone en Route 53"
  type        = bool
  default     = true
}

variable "existing_zone_id" {
  description = "ID de Hosted Zone existente si create_hosted_zone es false"
  type        = string
  default     = null
}

