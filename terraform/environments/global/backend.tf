terraform {
  backend "s3" {
    bucket       = "dr-proyecto-terraform-state-utb"
    key          = "global/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
