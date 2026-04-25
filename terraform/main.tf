data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"] # Official Amazon AWS account ID.

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source = "./modules/vpc"

  name                 = "greencart"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24"]
  azs                  = ["us-east-1a", "us-east-1b"]
}

module "security_groups" {
  source = "./modules/security_groups"
  name   = "greencart"
  vpc_id = module.vpc.vpc_id
}

module "ecr" {
  source = "./modules/ecr"

  repositories = ["backend", "frontend"]
}

module "iam" {
  source = "./modules/iam"

  github_owner        = "haimNemir"
  github_repo         = "GreenCart"
  ecr_repository_arns = values(module.ecr.repository_arns)
}

module "ec2_app" {
  source = "./modules/ec2_app"

  name                  = "greencart"
  ami_id                = data.aws_ami.al2023.id
  instance_type         = "t3.micro"
  subnet_ids            = module.vpc.public_subnet_ids
  security_group_id     = module.security_groups.app_sg_id
  instance_profile_name = module.iam.instance_profile_name
  public_key            = var.public_key
}

module "ec2_db" {
  source = "./modules/ec2_db"

  name              = "greencart"
  ami_id            = data.aws_ami.al2023.id
  instance_type     = "t3.micro"
  subnet_id         = module.vpc.private_subnet_id
  security_group_id = module.security_groups.db_sg_id
  key_pair_name     = module.ec2_app.key_pair_name
}

module "alb" {
  source = "./modules/alb"

  name              = "greencart"
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  instance_ids      = module.ec2_app.instance_ids
}
