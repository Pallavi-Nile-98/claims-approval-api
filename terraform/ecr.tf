resource "aws_ecr_repository" "app" {
  name = local.name

  # A tag always points at the same image (tags are git commit SHAs), so "what is
  # running?" always has one answer and a tag can't be silently overwritten.
  image_tag_mutability = "IMMUTABLE"

  # Basic scanning for known OS/package vulnerabilities on every push (free).
  image_scanning_configuration {
    scan_on_push = true
  }

  # Lets `terraform destroy` remove the repository even while it still holds images,
  # so nothing is left behind accruing storage charges.
  force_delete = true
}

# Keep only the 5 most recent images: enough to roll back, while storage stays near $0.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
