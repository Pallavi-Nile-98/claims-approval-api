# Three security groups chained by reference, not by IP range:
#
#   internet --80--> alb --8080--> app --5432--> db
#
# Referencing security groups instead of CIDRs means the rules keep working as Fargate
# tasks come and go with new IPs. Each rule is its own resource (not an inline block),
# so a single rule can be changed or removed without rewriting the whole group.
# Security groups are stateful: return traffic is allowed automatically, so only the
# direction that opens a connection needs a rule.

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Public HTTP into the load balancer"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "Fargate tasks: accept traffic only from the ALB"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-app" }
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "RDS: accept PostgreSQL only from the app"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-db" }
}

# ---------- ALB ----------

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere (HTTPS needs a domain + certificate, out of scope)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward requests and health checks to the app only"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.app.id
}

# ---------- App (Fargate) ----------

# The task has a public IP, but this is its ONLY inbound rule, so nothing on the
# internet can reach it directly: every request has to come through the ALB.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from the ALB only"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.alb.id
}

# Outbound HTTPS is needed to pull the image from ECR, fetch the DB password from SSM,
# ship logs to CloudWatch and use ECS Exec. Without a NAT gateway or VPC endpoints these
# go out through the internet gateway via the task's public IP. The AWS APIs have no
# fixed IP range to pin this to, hence 0.0.0.0/0 on port 443 only.
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs (ECR, SSM, CloudWatch Logs, ECS Exec)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL to RDS only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.db.id
}

# ---------- Database ----------

# The single rule that lets the app reach the database. Removing it is Phase 5 failure 1.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the app only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}

# No egress rules on the database: it never opens connections itself, and replies
# to the app are allowed automatically because security groups are stateful.
