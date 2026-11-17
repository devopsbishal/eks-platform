provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      environment = var.environment
      project     = var.project_name
      managed-by  = "terraform"
      owner       = "bishal"
      cost-center = "cloud-infrastructure"
    }
  }
}

module "vpc" {
  source                = "../../modules/vpc"
  vpc_name              = "eks-platform-dev"
  vpc_cidr              = "10.20.0.0/16"
  availability_zone_ids = ["use1-az1", "use1-az2", "use1-az4"]
}


output "private_subnet_ids" {
  description = "IDs of the private subnets the EKS cluster and nodes go in."
  value       = module.vpc.private_subnet_ids
}

output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.vpc.vpc_id
}
