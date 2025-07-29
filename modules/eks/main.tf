module "vpc" {
  source = "../../modules/vpc"

  name            = "dev-vpc"
  cidr_block      = "10.0.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

module "eks" {
  source  = "../../modules/eks"

  cluster_name    = "dev-eks-cluster"
  cluster_version = "1.28"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}
