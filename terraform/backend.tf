terraform { # Here we are defining where we will store our Terraform state file.
  backend "s3" {
    bucket         = "greencart-tfstate-haimnemir"
    key            = "terraform.tfstate" # key is the path within the bucket where the state file will be stored
    region         = "us-east-1"
    dynamodb_table = "greencart-tfstate-lock" # This line tells Terraform to use a DynamoDB table for state locking, and Terraform will create do the locking automatically, and we just need to make sure that the DynamoDB and S3 bucket are exist.
    encrypt        = true               # This ensures that the state file is encrypted at rest in S3. So if someone gains unauthorized access to the S3 phisical storage, they won't be able to read the state file without the proper decryption keys. but for me its automatically decrypted when I access it through Terraform, or if I access it through the AWS S3 console.
  }
}
