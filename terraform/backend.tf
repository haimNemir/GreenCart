terraform { # Here we are defining where we will store our Terraform state file.
  backend "s3" {
    bucket         = "greencart-tfstate-haimnemir"
    key            = "terraform.tfstate" # key is the path within the bucket where the state file will be stored
    region         = "us-east-1"
    dynamodb_table = "greencart-tfstate-lock"
    encrypt        = true
  }
}
