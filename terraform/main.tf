
module "network" {
  source      = "./modules/network"
  name        = "backend-network"
}

module "alb" {
  source      = "./modules/alb"
  name        = "backend-alb"
  vpc_id      = module.network.vpc.id
  subnet_ids  = [
    module.network.subnet_public0.id,
    module.network.subnet_public1.id
  ]
  root_domain_name = var.alb_root_domain_name
  subdomain_name = var.alb_subdomain_name
}

module "ecr" {
  source      = "./modules/ecr"
  repository_name = var.ecr_repository_name
}

module "ecs" {
  source      = "./modules/ecs"
  name        = "backend-ecs"
  vpc_id      = module.network.vpc.id
  vpc_cidr_block   = module.network.vpc.cidr_block
  subnet_ids  = [
    module.network.subnet_private0.id,
    module.network.subnet_private1.id
  ]
  container_port    = var.ecs_container_port
  container_definitions_json_filepath   = var.container_definitions_json_filepath
  lb_target_group_arn   = module.alb.alb_target_group_arn
  cpu = var.ecs_cpu
  memory = var.ecs_memory
  service_desired_count = var.ecs_service_desired_count
  container_name = var.ecs_container_name
}

module "codepipeline" {
  source      = "./modules/codepipeline"
  name        = "backend-codepipeline"
  bucket_name = var.codepipeline_bucket_name
  github_repo_name = var.codepipeline_github_repo_name
  github_branch_name = var.codepipeline_github_branch_name
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  github_token = var.GITHUB_TOKEN
  secret = var.codepipeline_secret
}
