terraform {
  # Fixes the required Terraform CLI version
  required_version = ">= 1.11"

  # Fixes the required provider versions
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # Allows minor updates (6.x), blocks breaking changes (7.0)
    }
  }
}
