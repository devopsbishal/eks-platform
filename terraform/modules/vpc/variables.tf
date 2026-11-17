variable "vpc_name" {
  description = "Name tag of the VPC; the upstream module also uses it as the prefix for subnet, route table and NAT gateway names."
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the VPC. Must be a /16: the module carves three private /20s and three public /24s out of it."
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.20.0.0/16."
  }

  validation {
    condition     = try(tonumber(split("/", var.vpc_cidr)[1]) == 16, false)
    error_message = "vpc_cidr must be exactly /16."
  }

  validation {
    # 3. IP part must be the network address (no host bits set)
    condition     = try(cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)[0], false)
    error_message = "vpc_cidr must be a network address, e.g. 10.20.0.0/16 rather than 10.20.5.0/16."
  }
}

variable "availability_zone_ids" {
  description = "Three distinct AZ IDs (e.g. use1-az1), not AZ names: IDs are the same physical zone in every account. Order matters: the single NAT gateway goes in the first one."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(distinct(var.availability_zone_ids)) == 3
    error_message = "Exactly 3 unique availability zones are required."
  }

  validation {
    condition     = !contains(var.availability_zone_ids, "use1-az3")
    error_message = "use1-az3 is not supported for EKS control plane subnets in us-east-1. Use other AZ IDs."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway ($0.045/h), in the first AZ of availability_zone_ids, shared by all private subnets; if that AZ fails, every AZ loses egress. Exactly one of this and one_nat_gateway_per_az must be true."
  type        = bool
  default     = true

  validation {
    condition     = !(var.single_nat_gateway && var.one_nat_gateway_per_az)
    error_message = "Cannot set both single_nat_gateway and one_nat_gateway_per_az to true."
  }

  validation {
    condition     = var.single_nat_gateway || var.one_nat_gateway_per_az
    error_message = "At least one of single_nat_gateway or one_nat_gateway_per_az must be true."
  }
}


variable "one_nat_gateway_per_az" {
  description = "One NAT gateway per AZ ($0.135/h for three), so an AZ failure only cuts egress in that AZ. Exactly one of this and single_nat_gateway must be true."
  type        = bool
  default     = false
}
