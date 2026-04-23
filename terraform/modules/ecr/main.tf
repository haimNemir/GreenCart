resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories) # toset converts the list to a set to avoid duplicates. The result looks like: { "backend" = "backend", "frontend" = "frontend" }

  name         = "greencart-${each.value}"
  force_delete = true # Allows deleting the repository even when it contains images — required for full teardown via destroy-infra.sh.

  image_scanning_configuration {
    scan_on_push = true # Enables image scanning on push, which helps identify vulnerabilities in container images as soon as they are pushed to the repository.
  }

  tags = {
    Project = "greencart"
  }
}
