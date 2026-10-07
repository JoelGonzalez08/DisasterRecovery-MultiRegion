# Subnet Group para la base de datos (subredes privadas de datos)
resource "aws_db_subnet_group" "this" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Subnet group para RDS MySQL en subredes privadas aisladas"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-db-subnet-group"
      Environment = var.environment
    }
  )
}

# Security Group para RDS: solo permite tráfico 3306 desde el Security Group de EC2
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Reglas de firewall para base de datos relacional RDS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Acceso MySQL desde instancias EC2 de la aplicacion"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-sg"
      Environment = var.environment
    }
  )
}

# Instancia RDS MySQL (soporta rol Writer Multi-AZ o Read Replica según variables)
resource "aws_db_instance" "this" {
  identifier = "${var.project_name}-${var.environment}-mysql"

  # Parámetros del motor (solo para la base primaria, la replica hereda de la fuente)
  engine         = var.is_read_replica ? null : "mysql"
  engine_version = var.is_read_replica ? null : "8.0"
  instance_class = var.instance_class

  allocated_storage     = var.is_read_replica ? null : var.allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"

  # Credenciales y esquema (no se especifican en una Read Replica)
  db_name  = var.is_read_replica ? null : var.db_name
  username = var.is_read_replica ? null : var.db_username
  password = var.is_read_replica ? null : var.db_password

  # Configuración de Alta Disponibilidad y Respaldo
  multi_az                = var.is_read_replica ? false : var.multi_az
  backup_retention_period = var.is_read_replica ? 0 : var.backup_retention_period
  replicate_source_db     = var.is_read_replica ? var.replicate_source_db : null

  # Red y Seguridad
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-mysql"
      Environment = var.environment
      Role        = var.is_read_replica ? "Read-Replica" : "Primary-Writer"
    }
  )
}
