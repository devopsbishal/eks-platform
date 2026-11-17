terraform {
  # Minimum Terraform CLI version
  required_version = ">= 1.11"

  # Provider versions
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28" # Floor only: terraform-aws-modules/vpc v6.7.3 needs 6.28+. The calling root sets the ceiling.
    }
  }
}
