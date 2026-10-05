terraform {
  backend "s3" {
    bucket         = "dr-proyecto-terraform-state-utb" # El nombre único del bucket
    key            = "primary/terraform.tfstate"       # Ruta del archivo dentro del bucket
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"            # El nombre de la tabla creada
    encrypt        = true                              # Encripta el estado en reposo
  }
}