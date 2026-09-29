provider "aws" {
  region = var.aws_region

  # Applied to every resource, so Cost Explorer can show exactly what this project
  # costs and a leftover-resource check after `destroy` can find anything by tag.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# The first two AZs in the region; ALB and the RDS subnet group both require two.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name       = var.project_name
  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
}
