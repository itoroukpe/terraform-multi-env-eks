terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }

  required_version = ">= 1.3.0"
}


provider "aws" {
  region = var.region
}

module "vpc" {
  source          = "../../modules/vpc"
  vpc_name        = "dev-vpc"
  vpc_cidr        = "10.10.0.0/16"
  azs             = ["us-west-2a", "us-west-2b"]
  public_subnets  = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnets = ["10.10.3.0/24", "10.10.4.0/24"]
  tags            = { Environment = "dev" }
}

module "eks" {
  source       = "../../modules/eks"
  cluster_name = "dev-eks-cluster"
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnets
  tags         = { Environment = "dev" }
}
