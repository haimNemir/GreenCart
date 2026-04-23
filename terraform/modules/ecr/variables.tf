variable "repositories" {
  type        = list(string)
  description = "List of ECR repository names to create (will be prefixed with 'greencart-')"
}
