# ---------- Password: generated, stored in SSM, never written to Terraform state ----------
#
# `ephemeral` resources exist only while Terraform runs and are never saved to state.
# The password is passed to RDS and SSM through write-only arguments (`*_wo`), which
# Terraform sends to AWS but does not record either. So neither the repo nor the local
# terraform.tfstate ever contains the password; the only copy lives in SSM, encrypted.
#
# The *_wo_version numbers control when the value is (re)sent. Both are sent together
# on the first apply, so RDS and SSM receive the same password. To rotate it, bump both
# versions in the same apply.

ephemeral "random_password" "db" {
  length = 32
  # RDS forbids '/', '@', '"' and spaces in master passwords.
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

locals {
  db_password_version = 1
}

# SecureString with the AWS-managed aws/ssm KMS key: encrypted at rest, and free
# (standard tier). Secrets Manager would add rotation for $0.40/month, not needed here.
resource "aws_ssm_parameter" "db_password" {
  name             = "/${local.name}/db/password"
  description      = "Master password for the ${local.name} RDS instance"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.db.result
  value_wo_version = local.db_password_version
}

# ---------- RDS PostgreSQL in the private subnets ----------

resource "aws_db_subnet_group" "main" {
  name        = "${local.name}-db"
  description = "Private subnets only: no route to or from the internet"
  subnet_ids  = aws_subnet.private[*].id
}

resource "aws_db_instance" "main" {
  identifier = "${local.name}-db"

  engine                     = "postgres"
  engine_version             = "16" # same major version as local dev and the tests
  auto_minor_version_upgrade = true
  instance_class             = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true # encryption at rest with the AWS-managed key, no extra cost

  db_name             = var.db_name
  username            = var.db_username
  password_wo         = ephemeral.random_password.db.result
  password_wo_version = local.db_password_version

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false # no public endpoint; reachable only from inside the VPC
  multi_az               = false # single-AZ to halve the cost; see README trade-offs

  # Lowest-cost settings for a demo. In production: longer retention, a final snapshot
  # and deletion protection. Here they would make `terraform destroy` leave things behind.
  backup_retention_period  = 1
  skip_final_snapshot      = true
  delete_automated_backups = true
  deletion_protection      = false
  apply_immediately        = true

  # Paid extras left off.
  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = { Name = "${local.name}-db" }
}
