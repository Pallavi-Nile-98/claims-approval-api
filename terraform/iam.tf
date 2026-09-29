# Two roles with different jobs, each with only what that job needs:
#
#   execution role - used by the ECS agent BEFORE the app starts: pull the image,
#                    fetch the DB password from SSM, create the log stream.
#   task role      - used by the application code WHILE it runs. The app itself calls
#                    no AWS APIs, so its only permissions are for ECS Exec (debug shell).
#
# A common mistake is granting secret access to the task role: secrets injected into
# the container's environment are fetched by the EXECUTION role.

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
}

# Both roles can only be assumed by ECS tasks, and only on behalf of this account.
# The SourceAccount condition blocks the "confused deputy" problem, where the service
# could be tricked into using this role for someone else's resources.
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# ---------- Execution role ----------

resource "aws_iam_role" "execution" {
  name               = "${local.name}-execution"
  description        = "ECS agent: pull image, read DB password, write logs"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "execution" {
  # WILDCARD, explained: GetAuthorizationToken returns a registry-wide login token and
  # does not support resource-level permissions, so AWS only accepts "*" here.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullAppImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # Scoped to this app's log group. The trailing "log-stream:*" is needed because ECS
  # names a new stream per task, so the stream names aren't known in advance.
  statement {
    sid       = "WriteAppLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:log-stream:*"]
  }

  # Exactly one parameter. Removing this statement is Phase 5 failure 2.
  # No kms:Decrypt needed: the parameter uses the AWS-managed aws/ssm key.
  statement {
    sid       = "ReadDbPassword"
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.db_password.arn]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "least-privilege"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# ---------- Task role ----------

resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  description        = "Application runtime: ECS Exec only"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "task" {
  # WILDCARD, explained: ECS Exec opens a session through SSM Session Manager channels.
  # These ssmmessages actions do not support resource-level permissions, so "*" is the
  # only accepted value. They grant no data access, only the ability to open a shell
  # session into this task for troubleshooting.
  statement {
    sid = "EcsExec"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
