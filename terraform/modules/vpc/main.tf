locals {
  subnet_cidrs         = cidrsubnets(var.vpc_cidr, 4, 4, 4, 8, 8, 8)
  private_subnet_cidrs = slice(local.subnet_cidrs, 0, 3)
  public_subnet_cidrs  = slice(local.subnet_cidrs, 3, 6)
  nat_gateway_enabled  = var.single_nat_gateway ? true : var.one_nat_gateway_per_az ? true : false
}

# AWS-0178 (no VPC flow logs), accepted risk: nothing records which connections
# were accepted or rejected, so a blocked security group rule or unexpected
# egress can't be traced after the fact. Flow logs need a log group and an IAM
# role, and ingestion is billed per GB; this VPC is destroyed after each session
# and carries no traffic but mine. Enable them before anyone else's traffic
# reaches it, with the standalone flow-log module: this module's built-in flow
# logs are deprecated and removed in v7.0.0.
#
# Only trivy's plan scan sees this (checked 2026-11-17): source scans count the
# module's disabled aws_flow_log block, and checkov's plan scan has no VPC check.
# A plan has no comments, so the plan-scan suppression is in .trivyignore.yaml.
#trivy:ignore:AVD-AWS-0178
module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=b3abd6df2ecf052451a361ed55b8f06f8742a795" # v6.7.3

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.availability_zone_ids
  private_subnets = local.private_subnet_cidrs
  public_subnets  = local.public_subnet_cidrs

  enable_nat_gateway     = local.nat_gateway_enabled
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az

  # EKS requires DNS hostnames and DNS support to be enabled in the VPC.
  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
}

# S3 gateway endpoint: free, unlike interface endpoints. ECR serves image layers
# from S3, so without it every node image pull goes through the NAT and is billed
# per GB. Private route tables only: the nodes are in the private subnets, and the
# public subnets reach S3 through the internet gateway, which has no per-GB charge.
# No endpoint policy, so all of S3 is reachable, the same access the NAT gives.
module "vpc_endpoints" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git//modules/vpc-endpoints?ref=b3abd6df2ecf052451a361ed55b8f06f8742a795" # v6.7.3

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
  }
}
