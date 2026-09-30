resource "aws_ecs_cluster" "main" {
  name = local.name

  # Container Insights adds per-task CloudWatch metrics at extra cost; the standard
  # ECS service metrics (CPU, memory) and the ALB metrics are enough here.
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

locals {
  container_name = "app"

  # RDS for PostgreSQL 15+ rejects unencrypted connections by default (rds.force_ssl),
  # so the driver is told to use TLS explicitly.
  db_url = "jdbc:postgresql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.db_name}?sslmode=require"
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # each task gets its own network interface and security group
  cpu                      = var.task_cpu
  memory                   = var.task_memory # set too low = Phase 5 failure 5

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  # x86 because the image is built on an x86 machine without multi-arch (buildx) support.
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = local.container_name
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    # Plain configuration. A wrong value here = Phase 5 failure 4.
    environment = [
      { name = "DB_URL", value = local.db_url },
      { name = "DB_USERNAME", value = var.db_username },
    ]

    # Fetched from SSM by the EXECUTION role when the task starts and injected as an
    # environment variable. The value never appears in the task definition or the console.
    secrets = [
      { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = local.container_name
      }
    }

    # Recommended for ECS Exec: a tiny init process that cleans up the shell sessions.
    linuxParameters = {
      initProcessEnabled = true
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = local.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  # platform_version is left unset: ECS then uses the latest Fargate platform. Setting it
  # to "LATEST" made every plan show a false diff, because AWS stores the resolved version.

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true # how the task reaches ECR/SSM/Logs without a NAT gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # A JVM on 0.25 vCPU takes roughly a minute to start and run migrations. Without a
  # grace period the ALB would mark it unhealthy mid-startup and ECS would kill it.
  health_check_grace_period_seconds = 180

  # Start the new task before stopping the old one, so a deploy has no downtime.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # If new tasks keep failing, stop retrying and roll back to the last working version.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  enable_execute_command  = true # `aws ecs execute-command` for a shell inside the task
  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE" # tasks inherit the Project tag for cost tracking

  # The target group must be attached to the load balancer before a service can use it.
  depends_on = [aws_lb_listener.http]
}
