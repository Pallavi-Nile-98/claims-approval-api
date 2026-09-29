resource "aws_lb" "main" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Reject requests with malformed headers instead of passing them to the app.
  drop_invalid_header_fields = true

  # Access logs to S3 are left off to avoid storage costs; CloudWatch metrics still work.
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # required for Fargate: tasks register by their private IP, not an instance

  health_check {
    path                = var.health_check_path # wrong path here = Phase 5 failure 3
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2 # healthy after ~30 s of passing checks
    unhealthy_threshold = 3 # unhealthy after ~45 s of failing checks
  }

  # How long the ALB keeps sending in-flight requests to a task being replaced. The
  # default 300 s would add 5 minutes to every deployment for no benefit here.
  deregistration_delay = 30
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
