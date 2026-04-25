resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket

  force_destroy = true # Allows Terraform to delete the bucket even when it contains the state file, which is required for the full teardown flow (destroy-infra.sh).
}


# Allows S3 to keep previous versions of the state file, which can be crucial for recovery in case of
# accidental deletion or overwriting of the state file. 
resource "aws_s3_bucket_versioning" "tfstate" { 
  bucket = aws_s3_bucket.tfstate.id     # Choose the bucket to enable versioning on. 
  versioning_configuration {
    status = "Enabled" 
  }
}

# Here we ask from AWS to always encrypt any object stored in this bucket using AES-256, And this 
# scope is bucket level.
# We also encrypt the state file in "terraform\backend.tf" in "encrypt = true", and its additional
# layer of encryption, but noth are not necessary.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Type of the encryption algorithm to use.
    }
  }
}

# Those settings block public access to the bucket, even the ACL and bucket policy allows it,
# This is an additional layer of security to prevent accidental exposure of the state file, and this 
# is so important because the state file contains sensitive information.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
