#!/usr/bin/env bash
# Push the image for the current commit to ECR.
# On the very first run, creates ONLY the ECR repository first: the ECS service needs an
# image to exist before its task can start, but ECR is managed by the same Terraform.
# Usage: bash scripts/push.sh   (after scripts/build.sh)
source "$(dirname "$0")/common.sh"

require_tools git docker aws terraform
require_aws_credentials

TAG=$(image_tag)
docker image inspect "$PROJECT:$TAG" >/dev/null 2>&1 \
  || die "Local image $PROJECT:$TAG not found. Run scripts/build.sh first."

if ! aws ecr describe-repositories --repository-names "$PROJECT" >/dev/null 2>&1; then
  log "First deploy: creating only the ECR repository. Review the plan, then type 'yes'."
  tf_init
  # A targeted apply is meant for exceptional cases, and bootstrapping is one of them.
  tf_run apply -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app
fi

REPO_URL=$(aws ecr describe-repositories --repository-names "$PROJECT" \
  --query 'repositories[0].repositoryUri' --output text)
REGISTRY="${REPO_URL%%/*}" # <account>.dkr.ecr.<region>.amazonaws.com

# Tags are immutable, so pushing the same tag twice would fail. Skip if it's already there.
if aws ecr describe-images --repository-name "$PROJECT" --image-ids "imageTag=$TAG" >/dev/null 2>&1; then
  log "$REPO_URL:$TAG is already in ECR, nothing to push."
  exit 0
fi

log "Logging in to $REGISTRY"
# The token goes through stdin, so it never appears in the process list or shell history.
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"

log "Pushing $REPO_URL:$TAG"
docker tag "$PROJECT:$TAG" "$REPO_URL:$TAG"
docker push "$REPO_URL:$TAG"
log "Pushed $REPO_URL:$TAG"
