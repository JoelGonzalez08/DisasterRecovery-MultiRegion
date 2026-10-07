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

# Generador de sufijo aleatorio para garantizar unicidad global en S3
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 1. Red y Conectividad (VPC Primaria en us-east-1)
module "vpc" {
  source = "../../modules/vpc"

  project_name              = var.project_name
  environment               = var.environment
  vpc_cidr                  = "10.0.0.0/16"
  public_subnet_cidrs       = ["10.0.1.0/24", "10.0.2.0/24"]
  private_app_subnet_cidrs  = ["10.0.11.0/24", "10.0.12.0/24"]
  private_data_subnet_cidrs = ["10.0.21.0/24", "10.0.22.0/24"]

  tags = {
    Region = var.aws_region
  }
}

# 2. Almacenamiento de Objetos S3 (Versionado habilitado para CRR)
module "storage_s3" {
  source = "../../modules/storage_s3"

  bucket_name       = "${var.s3_bucket_prefix}-${random_id.bucket_suffix.hex}"
  environment       = var.environment
  enable_versioning = true

  tags = {
    Region = var.aws_region
    Role   = "Source-Bucket"
  }
}

# 3. Base de Datos NoSQL DynamoDB (Streams habilitados para Global Tables)
resource "aws_dynamodb_table" "user_sessions" {
  name             = "user_sessions"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "user_id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "user_id"
    type = "S"
  }

  tags = {
    Name        = "user_sessions"
    Environment = var.environment
    Region      = var.aws_region
  }
}

# 4. Base de Datos Relacional RDS MySQL (Multi-AZ Primario Writer)
module "database_rds" {
  source = "../../modules/database_rds"

  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_data_subnet_ids
  app_security_group_id   = module.compute_alb_asg.ec2_security_group_id
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = "transactions_db"
  db_username             = var.db_username
  db_password             = var.db_password
  multi_az                = true
  backup_retention_period = 7
  is_read_replica         = false

  tags = {
    Region = var.aws_region
  }
}

# 5. Capa de Cómputo (ALB + EC2 Auto Scaling Group con API Contenerizada)
module "compute_alb_asg" {
  source = "../../modules/compute_alb_asg"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_app_subnet_ids

  instance_type     = "t3.micro"
  min_size          = 2
  max_size          = 4
  desired_capacity  = 2
  app_port          = 8000
  health_check_path = "/health"

  db_host      = module.database_rds.db_address
  db_port      = module.database_rds.db_port
  db_user      = var.db_username
  db_pass      = var.db_password
  db_name      = "transactions_db"
  dynamo_table = aws_dynamodb_table.user_sessions.name
  s3_bucket    = module.storage_s3.bucket_name
  aws_region   = var.aws_region

  tags = {
    Region = var.aws_region
  }
}
