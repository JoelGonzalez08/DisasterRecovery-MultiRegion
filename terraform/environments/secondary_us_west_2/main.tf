terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Provider principal para la región secundaria (us-west-2)
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
      Team      = "UTB-DR-Team"
    }
  }
}

# Provider secundario apuntando a us-east-1 para registrar la regla S3 CRR en el bucket origen
provider "aws" {
  alias  = "primary"
  region = var.primary_aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
      Team      = "UTB-DR-Team"
    }
  }
}

# Lectura del estado remoto de la Región Primaria (us-east-1)
data "terraform_remote_state" "primary" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.primary_state_key
    region = var.primary_aws_region
  }
}

# Generador de sufijo aleatorio para garantizar unicidad global del bucket réplica en S3
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# --------------------------------------------------------------------------
# 1. Red y Conectividad (VPC Secundaria en us-west-2 con CIDR no solapado)
# --------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project_name              = var.project_name
  environment               = var.environment
  vpc_cidr                  = "10.1.0.0/16"
  public_subnet_cidrs       = ["10.1.1.0/24", "10.1.2.0/24"]
  private_app_subnet_cidrs  = ["10.1.11.0/24", "10.1.12.0/24"]
  private_data_subnet_cidrs = ["10.1.21.0/24", "10.1.22.0/24"]

  tags = {
    Region = var.aws_region
  }
}

# --------------------------------------------------------------------------
# 2. Almacenamiento S3 Réplica + Regla Cross-Region Replication (CRR)
# --------------------------------------------------------------------------
module "storage_s3" {
  source = "../../modules/storage_s3"

  bucket_name       = "${var.s3_bucket_prefix}-${random_id.bucket_suffix.hex}"
  environment       = var.environment
  enable_versioning = true

  tags = {
    Region = var.aws_region
    Role   = "Replica-Bucket"
  }
}

resource "aws_iam_role" "s3_crr" {
  name = "${var.project_name}-s3-crr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "s3_crr" {
  name        = "${var.project_name}-s3-crr-policy"
  description = "Permisos para replicar objetos S3 desde us-east-1 hacia us-west-2"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [data.terraform_remote_state.primary.outputs.s3_bucket_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = ["${data.terraform_remote_state.primary.outputs.s3_bucket_arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = ["${module.storage_s3.bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_crr" {
  role       = aws_iam_role.s3_crr.name
  policy_arn = aws_iam_policy.s3_crr.arn
}

resource "aws_s3_bucket_replication_configuration" "primary_to_secondary" {
  provider = aws.primary

  role   = aws_iam_role.s3_crr.arn
  bucket = data.terraform_remote_state.primary.outputs.s3_bucket_name

  rule {
    id     = "crr-primary-to-secondary-invoices"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = module.storage_s3.bucket_arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [
    module.storage_s3,
    aws_iam_role_policy_attachment.s3_crr
  ]
}

# --------------------------------------------------------------------------
# 3. DynamoDB Global Table Replica (Replicación Activa-Activa en us-west-2)
# --------------------------------------------------------------------------
resource "aws_dynamodb_table_replica" "user_sessions" {
  global_table_arn = data.terraform_remote_state.primary.outputs.dynamodb_table_arn

  tags = {
    Name        = data.terraform_remote_state.primary.outputs.dynamodb_table_name
    Environment = var.environment
    Region      = var.aws_region
    Role        = "Global-Table-Replica"
  }
}

# --------------------------------------------------------------------------
# 4. Base de Datos Relacional RDS MySQL (Read Replica Cross-Region)
# --------------------------------------------------------------------------
module "database_rds" {
  source = "../../modules/database_rds"

  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_data_subnet_ids
  app_security_group_id   = module.compute_alb_asg.ec2_security_group_id
  instance_class          = "db.t3.micro"
  multi_az                = false
  backup_retention_period = 7
  is_read_replica         = true
  replicate_source_db     = data.terraform_remote_state.primary.outputs.rds_arn

  tags = {
    Region = var.aws_region
  }
}

# --------------------------------------------------------------------------
# 5. Capa de Cómputo en Warm Standby (ALB activo + ASG en desired_capacity = 0)
# --------------------------------------------------------------------------
module "compute_alb_asg" {
  source = "../../modules/compute_alb_asg"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_app_subnet_ids

  instance_type     = "t3.micro"
  min_size          = 0
  max_size          = 4
  desired_capacity  = 0
  app_port          = 8000
  health_check_path = "/health"

  db_host      = module.database_rds.db_address
  db_port      = module.database_rds.db_port
  db_user      = var.db_username
  db_pass      = var.db_password
  db_name      = "transactions_db"
  dynamo_table = data.terraform_remote_state.primary.outputs.dynamodb_table_name
  s3_bucket    = module.storage_s3.bucket_name
  aws_region   = var.aws_region

  tags = {
    Region = var.aws_region
  }
}

