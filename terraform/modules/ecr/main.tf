
resource "aws_ecr_repository" "web_backend" {
  name = var.repository_name
}

resource "aws_ecr_lifecycle_policy" "web_backend" {
  repository = aws_ecr_repository.web_backend.name

  policy = <<EOF
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "Keep last 30 release tagged images",
        "selection": {
          "tagSelection": "tagged",
          "tagPrefixList": ["release"],
          "countType": "imageCountMoreThan",
          "countNumber": 30
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
EOF
}

##############

output "repository_name" {
  value = aws_ecr_repository.web_backend.name
}
