#!/usr/bin/env bash
# Shared settings and helpers, sourced by the other scripts. Not meant to be run directly.

# Stop on the first failing command, on unset variables, and on failures inside pipes.
set -euo pipefail

# Git Bash on Windows rewrites arguments that look like Unix paths, turning the log group
# "/ecs/claims-approval-api" into "C:/Program Files/Git/ecs/...". Disable that.
export MSYS_NO_PATHCONV=1

# Print AWS CLI output directly instead of opening it in a pager.
export AWS_PAGER=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Because path conversion is off, native Windows tools (git, docker, terraform) need
# "C:/Users/..." rather than Git Bash's "/c/Users/...". `pwd -W` gives that form on
# Git Bash; on macOS/Linux it doesn't exist, so fall back to plain `pwd`.
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && { pwd -W 2>/dev/null || pwd; })"
TF_DIR="$REPO_ROOT/terraform"
PROJECT="claims-approval-api"
export AWS_REGION="${AWS_REGION:-us-east-2}"

# Converts a Git Bash path (/tmp/x) into one native Windows tools can open (C:/.../x),
# since path conversion is disabled above. A no-op on macOS/Linux, which lack cygpath.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' is not installed or not on PATH."
  done
}

# Fail fast with a clear message instead of a confusing error halfway through a deploy.
require_aws_credentials() {
  local arn
  arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) \
    || die "AWS credentials are not working. Run 'aws configure', then check with 'aws sts get-caller-identity'."
  case "$arn" in
    *:root) die "These are ROOT user credentials. Create an IAM user and use its access key instead." ;;
  esac
  log "AWS identity: $arn (region $AWS_REGION)"
}

# Images are tagged with the commit they were built from, so a running task can always
# be traced back to the exact code.
image_tag() { git -C "$REPO_ROOT" rev-parse --short=12 HEAD; }

require_clean_tree() {
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    git -C "$REPO_ROOT" status --short >&2
    die "Uncommitted changes (above). Commit them first, so the image tag matches exactly what is in git."
  fi
}

tf() { terraform -chdir="$TF_DIR" "$@"; }
tf_init() { tf init -input=false >/dev/null; }
tf_output() { tf output -raw "$1"; }

# Runs plan/apply/destroy with the variables every one of them needs.
# -var overrides terraform.tfvars. Usage: tf_run apply [-target=...]
tf_run() {
  local command=$1
  shift
  tf "$command" -var "image_tag=$(image_tag)" -var "aws_region=$AWS_REGION" "$@"
}
