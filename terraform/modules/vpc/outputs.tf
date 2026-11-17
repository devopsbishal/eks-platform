output "private_subnet_ids" {
  description = "IDs of the three private subnets, in availability_zone_ids order. Input for the EKS cluster and node group."
  value       = module.vpc.private_subnets
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}
