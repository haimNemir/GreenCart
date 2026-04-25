# Define the DynamoDB table for Terraform state locking so two developers don't step on each 
# other's changes. 

resource "aws_dynamodb_table" "locks" {
  name         = local.table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
