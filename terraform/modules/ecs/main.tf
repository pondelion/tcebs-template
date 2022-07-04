
data "aws_iam_policy_document" "ecs_task_policy" {
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
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
  }
}

module "ecs_task_exec_role" {
  source = "../iam"
  name = "terraform-test-ecs-task"
  identifier = "ecs-tasks.amazonaws.com"
  policy = data.aws_iam_policy_document.ecs_task_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = "${module.ecs_task_exec_role.iam_role_name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

module "ecs_sg" {
  source      = "../security_group"
  name        = "ecs-sg"
  vpc_id      = var.vpc_id
  port        = var.container_port
  cidr_blocks = [var.vpc_cidr_block] 
}

resource "aws_ecs_cluster" "web_ecs_cluster" {
  name = var.name
}

data "template_file" "container_definitions" {
  template = "${file("${var.container_definitions_json_filepath}")}"

#   vars = {
#     image_url = "${var.image_url}",
#     container_port = var.container_port
#   }
}

resource "aws_ecs_task_definition" "web_ecs_task_def" {
  family                        = "web_ecs_task_def"
  cpu                           = var.cpu
  memory                        = var.memory
  network_mode                  = "awsvpc"
  requires_compatibilities      = ["FARGATE"]
  container_definitions         = "${data.template_file.container_definitions.rendered}"
  task_role_arn                 = "${module.ecs_task_exec_role.iam_role_arn}"
  execution_role_arn            = "${module.ecs_task_exec_role.iam_role_arn}"
}

resource "aws_ecs_service" "web_ecs_svc" {
  name                          = "web_ecs_svc"
  cluster                       = aws_ecs_cluster.web_ecs_cluster.arn
  task_definition               = aws_ecs_task_definition.web_ecs_task_def.arn
  desired_count                 = var.service_desired_count
  launch_type                   = "FARGATE"
  platform_version              = "1.3.0"
  health_check_grace_period_seconds = 60

  network_configuration {
    assign_public_ip      = false
    security_groups       = [module.ecs_sg.security_group_id]
    # subnets               = [
    #   aws_subnet.private_0.id,
    #   aws_subnet.private_1.id,
    # ]
    subnets = var.subnet_ids
  }

  load_balancer {
    target_group_arn      = var.lb_target_group_arn
    container_name        = var.container_name
    container_port        =  var.container_port
  }

  lifecycle {
    ignore_changes  = [task_definition]
  }
}

####################

output "cluster_name" {
  value = aws_ecs_cluster.web_ecs_cluster.name
}

output "service_name" {
  value = aws_ecs_service.web_ecs_svc.name
}
