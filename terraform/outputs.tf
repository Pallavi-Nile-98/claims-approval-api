# Values needed by the deploy scripts (Phase 4) and for troubleshooting (Phase 5).
# Nothing secret is output: the DB password only exists in SSM.

output "alb_url" {
  description = "Public URL of the API"
  value       = "http://${aws_lb.main.dns_name}"
}

output "swagger_url" {
  description = "Swagger UI through the load balancer"
  value       = "http://${aws_lb.main.dns_name}/swagger-ui.html"
}

output "ecr_repository_url" {
  description = "Where to push the image (docker tag/push target)"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "task_definition_arn" {
  description = "Revision just deployed; compared with what ECS is running to detect a rollback"
  value       = aws_ecs_task_definition.app.arn
}

output "log_group_name" {
  description = "For: aws logs tail <name> --follow"
  value       = aws_cloudwatch_log_group.app.name
}

output "target_group_arn" {
  description = "For: aws elbv2 describe-target-health --target-group-arn <arn>"
  value       = aws_lb_target_group.app.arn
}

output "rds_endpoint" {
  description = "Private DNS name of the database (resolves only to private IPs)"
  value       = aws_db_instance.main.address
}

output "db_password_parameter" {
  description = "SSM parameter holding the DB password (name only, never the value)"
  value       = aws_ssm_parameter.db_password.name
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}

output "execution_role_name" {
  value = aws_iam_role.execution.name
}

output "task_role_name" {
  value = aws_iam_role.task.name
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.alb_5xx.alarm_name
}
