terraform {
  backend "s3" {
    bucket         = "meu-bucket-ansible1"
    key            = "ansible/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "lock-ansible"
    encrypt        = true
    acl            = "private"
  }
}
