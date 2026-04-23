variable "github_owner" { # The owner of the GitHub account.
  type        = string
  description = "GitHub org/user name"
}

variable "github_repo" { # The name of the GitHub repository — used to grant minimal permissions to GitHub Actions for this repo only.
  type        = string
  description = "GitHub repository name"
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "List of ECR repository ARNs that GitHub Actions can push to"
}
