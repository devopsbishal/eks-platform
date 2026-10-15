variable "aws_profile" {
  description = "The AWS profile to use for authentication"
  type        = string
  nullable    = false
}

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
  nullable    = false

  # 3–63 chars; lowercase letters, numbers, dots, hyphens;
  # must start and end with a letter or number
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.s3_bucket_name))
    error_message = "Bucket name must be 3-63 characters, use only lowercase letters, numbers, dots (.) and hyphens (-), and begin and end with a letter or number."
  }

  # No consecutive dots
  validation {
    condition     = !can(regex("\\.\\.", var.s3_bucket_name))
    error_message = "Bucket name must not contain consecutive dots."
  }
}

variable "subscriber_email" {
  description = "The email address to receive budget notifications"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.subscriber_email))
    error_message = "The subscriber email must be a valid email address."
  }
}


variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "eks-platform"
}

variable "environment" {
  description = "The environment for the deployment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

