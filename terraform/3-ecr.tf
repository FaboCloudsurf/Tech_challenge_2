# App container image storage
# stores the app Docker images.
resource "aws_ecr_repository" "ecr_app" {
  name                 = "${var.project_name}-ecr-app"
  image_tag_mutability = "MUTABLE"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

   tags = {
    Name        = "${var.project_name}-ecr-app"
    Environment = var.environment
    }
}


# Automatic cleanup for app images
# This rule automatically deletes old app images so the repository doesn’t keep growing forever.
# It keeps only the 5 most recent images whose tags start with "v" (for example v1.0, v1.1, etc.).
resource "aws_ecr_lifecycle_policy" "ecr_policy" {
  repository = aws_ecr_repository.ecr_app.name

  policy = jsonencode({

    rules = [
    {
      rulePriority = 1
      description = "Keep last 10 images"
      selection = {
        tagStatus = "any"
        #tagPrefixList = ["v"]
        countType = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"                       # Delete the older images
        }
      }
    ]
  })
}  
   
  

