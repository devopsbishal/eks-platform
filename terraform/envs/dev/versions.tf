terraform {
  # Minimum Terraform CLI version
  required_version = ">= 1.11"

  # Provider versions
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # Ceiling: any 6.x, never 7.0. The exact version is pinned in .terraform.lock.hcl.
    }
  }
}
