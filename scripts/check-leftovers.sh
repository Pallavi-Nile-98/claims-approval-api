#!/usr/bin/env bash
# Answers "am I still paying for anything?" after a destroy.
# Looks up each resource by name (reliable), then lists anything still carrying the
# Project tag (informational: the tagging API can lag behind deletions for a while).
# Usage: bash scripts/check-leftovers.sh     Exit code 1 = something still exists.
source "$(dirname "$0")/common.sh"

require_tools aws
require_aws_credentials

LEFTOVERS=0

# check <description> <aws command that prints something only if the resource exists>
check() {
  local what=$1
  shift
  local found
  found=$("$@" 2>/dev/null || true) # "not found" errors simply mean it's gone
  if [ -n "$found" ] && [ "$found" != "None" ]; then
    printf '  STILL EXISTS  %-34s %s\n' "$what" "$found"
    LEFTOVERS=$((LEFTOVERS + 1))
  else
    printf '  gone          %s\n' "$what"
  fi
}

log "Checking for leftover $PROJECT resources in $AWS_REGION"

# Billed by the hour, the ones that matter most:
check "Load balancer (~\$17/month)" aws elbv2 describe-load-balancers --names "$PROJECT-alb" \
  --query 'LoadBalancers[].LoadBalancerName' --output text
check "RDS instance (~\$14/month)" aws rds describe-db-instances --db-instance-identifier "$PROJECT-db" \
  --query 'DBInstances[].DBInstanceStatus' --output text
check "ECS service / tasks (~\$11/month)" aws ecs describe-services --cluster "$PROJECT" --services "$PROJECT" \
  --query "services[?status=='ACTIVE'].serviceName" --output text
# The VPC can only be deleted once every network interface (and so every public IPv4) is gone.
check "VPC and its public IPs" aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$PROJECT" \
  --query 'Vpcs[].VpcId' --output text

# Cost little or nothing, but should not be left behind:
check "RDS manual snapshots" aws rds describe-db-snapshots --snapshot-type manual \
  --query "DBSnapshots[?DBInstanceIdentifier=='$PROJECT-db'].DBSnapshotIdentifier" --output text
check "ECS cluster" aws ecs describe-clusters --clusters "$PROJECT" \
  --query "clusters[?status=='ACTIVE'].clusterName" --output text
check "ECR repository" aws ecr describe-repositories --repository-names "$PROJECT" \
  --query 'repositories[].repositoryName' --output text
check "SSM parameter" aws ssm get-parameters --names "/$PROJECT/db/password" \
  --query 'Parameters[].Name' --output text
check "CloudWatch log group" aws logs describe-log-groups --log-group-name-prefix "/ecs/$PROJECT" \
  --query 'logGroups[].logGroupName' --output text
check "CloudWatch alarm" aws cloudwatch describe-alarms --alarm-names "$PROJECT-alb-5xx" \
  --query 'MetricAlarms[].AlarmName' --output text

# Inactive ECS task definition revisions stay listed forever but cost nothing, so skip them.
log "Anything else still tagged Project=$PROJECT (may lag a few minutes behind deletions):"
aws resourcegroupstaggingapi get-resources --tag-filters "Key=Project,Values=$PROJECT" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n' \
  | grep -v ':task-definition/' | grep . | sed 's/^/  /' || echo "  (none)"

if [ "$LEFTOVERS" -eq 0 ]; then
  log "Nothing billable is left. You are not paying for this project."
else
  die "$LEFTOVERS resource(s) still exist. If one is 'deleting', wait a few minutes and run this again."
fi
