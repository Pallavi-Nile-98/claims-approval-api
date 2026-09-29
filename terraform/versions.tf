terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    # Generates the database password so no human ever types or commits it.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # State is kept locally (terraform.tfstate, gitignored): one person, one environment.
  # For a team this would be an S3 backend with encryption and state locking.
}
