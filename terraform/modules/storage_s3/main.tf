resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.enable_force_destroy

  tags = merge(
    var.tags,
    {
      Name        = var.bucket_name
      Environment = var.environment
    }
  )
}

# Versionado: Obligatorio para soportar Cross-Region Replication (CRR) en la Fase 2
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Cifrado en reposo con SSE-S3 (AES-256)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloqueo total de acceso público (Seguridad por defecto)
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------
# Cross-Region Replication (CRR) - Opcional cuando se provee bucket destino
# --------------------------------------------------------------------------
resource "aws_iam_role" "replication" {
  count = var.enable_replication && var.destination_bucket_arn != null ? 1 : 0
  name  = "${var.bucket_name}-crr-role"

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

  tags = merge(
    var.tags,
    {
      Name        = "${var.bucket_name}-crr-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_policy" "replication" {
  count       = var.enable_replication && var.destination_bucket_arn != null ? 1 : 0
  name        = "${var.bucket_name}-crr-policy"
  description = "Politica IAM para Cross-Region Replication de S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [aws_s3_bucket.this.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = ["${aws_s3_bucket.this.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = ["${var.destination_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  count      = var.enable_replication && var.destination_bucket_arn != null ? 1 : 0
  role       = aws_iam_role.replication[0].name
  policy_arn = aws_iam_policy.replication[0].arn
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.enable_replication && var.destination_bucket_arn != null ? 1 : 0

  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "replicate-all-invoices"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = var.destination_bucket_arn
      storage_class = var.destination_storage_class
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
