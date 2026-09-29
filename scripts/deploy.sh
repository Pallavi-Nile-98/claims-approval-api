#!/usr/bin/env bash
# Build, push and deploy the current commit, then verify it through the load balancer.
# Terraform always shows its plan and waits for you to type 'yes'. Nothing is auto-approved.
# Usage: bash scripts/deploy.sh
source "$(dirname "$0")/common.sh"

require_tools git docker aws terraform curl
require_aws_credentials

bash "$SCRIPT_DIR/build.sh"
bash "$SCRIPT_DIR/push.sh"

TAG=$(image_tag)
tf_init
log "Applying infrastructure for image $TAG. Review the plan, then type 'yes'."
log "(The first apply takes ~10-15 minutes, mostly creating the RDS instance.)"
tf_run apply

CLUSTER=$(tf_output ecs_cluster_name)
SERVICE=$(tf_output ecs_service_name)
EXPECTED_TASK_DEF=$(tf_output task_definition_arn)

log "Waiting for ECS to report the service stable (up to 10 minutes)..."
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" \
  || die "Service did not stabilise. Look at: aws ecs describe-services --cluster $CLUSTER --services $SERVICE --query 'services[0].events[:10]'"

# "Stable" can also mean the circuit breaker rolled back to the PREVIOUS version, so
# confirm the revision actually running is the one this deploy registered.
RUNNING_TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].deployments[?status==`PRIMARY`].taskDefinition | [0]' --output text)
[ "$RUNNING_TASK_DEF" = "$EXPECTED_TASK_DEF" ] \
  || die "ECS rolled back: running $RUNNING_TASK_DEF, expected $EXPECTED_TASK_DEF. Check the service events and: aws logs tail $(tf_output log_group_name) --since 30m"

log "Running $TAG ($RUNNING_TASK_DEF)"
bash "$SCRIPT_DIR/verify.sh"

log "Deployed. API: $(tf_output alb_url)   Swagger: $(tf_output swagger_url)"
log "Remember: 'bash scripts/destroy.sh' when you are done, to stop all charges."
