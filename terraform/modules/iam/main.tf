data "aws_caller_identity" "current" {} # Get the current AWS account ID

# ---- GitHub OIDC Provider ----

resource "aws_iam_openid_connect_provider" "github" { # Create inside IAM an OIDC provider for GitHub Actions. This allows GitHub Actions to authenticate with AWS using OIDC tokens. This means that if GitHub Actions creates a token to connect to AWS, AWS will trust that token and allow connections from GitHub Actions.
  url = "https://token.actions.githubusercontent.com" # This URL is the endpoint for GitHub Actions OIDC tokens. When GitHub Actions requests a token, it will be issued by this provider, and AWS will validate it against this URL.

  client_id_list = [ # Here we specify who can use this OIDC provider, in this case the STS service of AWS that decodes the OIDC token and allows GitHub Actions to assume the IAM role we create below.
    "sts.amazonaws.com",
  ]

  thumbprint_list = [                           # In the console this value is defined by default. This allows AWS to save the "fingerprint" of the server that connects to AWS, and if the server changes the connection will be rejected. This is a security measure.
    "6938fd4d98bab03faadb97b34396831e3780aea1", # To get this fingerprint you can check the AWS documentation for GitHub OIDC.
  ]
}

# ---- GitHub Actions IAM Role (ECR Push) ----

data "aws_iam_policy_document" "github_assume_role" { # This data source creates locally a JSON document that defines the trust policy for the GitHub Actions IAM role below.
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"] # This policy allows the role to be assumed by a web identity such as a GitHub Actions token.

    ## Allows the external GitHub identity to get access to AWS resources.
    principals {                # Principals in IAM define who can assume the role. Here we specify a federated identity provider — the OIDC provider we created above for GitHub Actions.
      type        = "Federated" # Federated is the opposite of an internal AWS user or service. This means the principal is an external identity such as GitHub Actions.
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    # Conditions in IAM policies specify additional rules that must be met for the policy to take effect.
    ## Check for audience.
    condition {                                            # We check that the audience in the OIDC token is exactly "sts.amazonaws.com".
      test     = "StringEquals"                            # "StringEquals" = word-for-word, without regex.
      variable = "token.actions.githubusercontent.com:aud" # This variable returns the "audience" claim in the OIDC token.
      values   = ["sts.amazonaws.com"]
    }
    ## Check for repository and ref (branch or tag).
    condition {
      test     = "StringLike"                              # "StringLike" allows regex, such as "refs/tags/v*" to match all tags starting with "v".
      variable = "token.actions.githubusercontent.com:sub" # Returns the "subject" claim in the OIDC token, containing the repository and ref that triggered the workflow.
      values = [
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/tags/v*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "greencart-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json # Create the IAM role with the trust policy document we created above.
}

data "aws_iam_policy_document" "ecr_push" {
  statement { # Policies that allow GitHub Actions to authenticate with ECR and push images.
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken", # This allows GitHub to authenticate with ECR.
    ]
    resources = ["*"] # GetAuthorizationToken is a global operation — it is not scoped to a specific repository.
  }

  statement {
    effect = "Allow"
    actions = [ # List of actions that allow pushing images to ECR.
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
    ]
    resources = var.ecr_repository_arns # The list of repo ARNs — only for these repositories GitHub Actions will have permission to push images.
  }
}

resource "aws_iam_policy" "ecr_push" { # Create the policy we defined above, but do not attach it to the role yet.
  name   = "greencart-github-actions-ecr-push"
  policy = data.aws_iam_policy_document.ecr_push.json
}

resource "aws_iam_role_policy_attachment" "github_ecr_push" { # Attach the ECR push policy to the GitHub Actions role.
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

# ---- EC2 Instance Profile (ECR Pull) ----

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"] # Only EC2 instances can assume this role.
    }
  }
}

resource "aws_iam_role" "ec2_app" {
  name               = "greencart-ec2-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_read" { # Attach the AWS managed ECR read policy to the EC2 role, allowing the app instances to pull images from ECR.
  role       = aws_iam_role.ec2_app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_app" { # The instance profile wraps the IAM role and is the mechanism by which an EC2 instance is associated with an IAM role.
  name = "greencart-ec2-app"
  role = aws_iam_role.ec2_app.name
}
