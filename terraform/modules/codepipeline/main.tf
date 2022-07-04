
resource "aws_s3_bucket" "deploy_bucket" {
  bucket = var.bucket_name
  force_destroy = true
  versioning {
    enabled = true
  }
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
  }
}

module "codebuild_role" {
  source = "../iam"
  name = "terraform-test-codebuild"
  identifier = "codebuild.amazonaws.com"
  policy = data.aws_iam_policy_document.codebuild.json
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "iam:PassRole",
    ]
  }
}

module "codepipeline_role" {
  source = "../iam"
  name = "terraform-test-codepipeline"
  identifier = "codepipeline.amazonaws.com"
  policy = data.aws_iam_policy_document.codepipeline.json
}

resource "aws_codebuild_project" "backend" {
  name          = var.name
  description   = "terraform-codepipeline-ecs-backend-test"
#   build_timeout = "60"
  service_role  = module.codebuild_role.iam_role_arn

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  source {
    type                        = "CODEPIPELINE"
  }

  artifacts {
    type                        = "CODEPIPELINE"
  }
}


resource "aws_codepipeline" "backend" {
  name = "terraform-codepipeline-ecs-backend-test"
  role_arn = module.codepipeline_role.iam_role_arn

  artifact_store {
    location = aws_s3_bucket.deploy_bucket.id
    type = "S3"
  }

  stage {
    name = "Source"

    action {
      name = "Source"
      category = "Source"
      owner = "ThirdParty"
      provider = "GitHub"
      version = 1
      output_artifacts = [ "Source" ]
      configuration = {
        OAuthToken = var.github_token
        Owner = "pondelion"
        Repo = var.github_repo_name
        Branch = var.github_branch_name
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["Source"]
      output_artifacts = ["Build"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.backend.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "ECS"
      version          = "1"
      input_artifacts = ["Build"]

      configuration = {
        ClusterName = var.ecs_cluster_name
        ServiceName = var.ecs_service_name
        FileName = "imagedefinitions.json"
      }
    }
  }
}

resource "aws_codepipeline_webhook" "backend" {
  name = "backend"
  target_pipeline = aws_codepipeline.backend.name
  target_action = "Source"
  authentication = "GITHUB_HMAC"

  authentication_configuration {
    secret_token = var.secret
  }

  filter {
    json_path = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

provider "github" {
  owner      = "pondelion"
  token      = var.github_token
}

resource "github_repository_webhook" "backend" {
  repository = var.github_repo_name

  configuration {
    url = aws_codepipeline_webhook.backend.url
    secret = var.secret
    content_type = "json"
    insecure_ssl = false
  }

  events = ["push"]
}

output "codepipeline_webhook_url" {
  value = aws_codepipeline_webhook.backend.url
}

output "github_repository_webhook_url" {
  value = github_repository_webhook.backend.url
}