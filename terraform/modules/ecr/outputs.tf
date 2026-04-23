output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" { # Gets the ARNs of our repos in AWS, used to scope the GitHub Actions ECR push permissions.
  value = { for k, r in aws_ecr_repository.this : k => r.arn }
}
