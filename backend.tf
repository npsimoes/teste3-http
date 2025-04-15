terraform {
  backend "s3" {
    bucket         = "meu-bucket-terraform-github-actions-uc-20" # Nome do S3 Bucket onde será armazenado o estado
    key            = "terraform.tfstate"                         # Caminho dentro do bucket
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-20" # Usado para evitar concorrência no estado
    encrypt        = true
    acl    = "private"
  }
}

