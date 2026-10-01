#!/usr/bin/env bash
# Build the Docker image, tagged with the current git commit SHA.
# Usage: bash scripts/build.sh
source "$(dirname "$0")/common.sh"

require_tools git docker
docker info >/dev/null 2>&1 \
  || die "Docker is installed but not running. Start Docker Desktop, wait for 'Engine running', then retry."
require_clean_tree

TAG=$(image_tag)
log "Building $PROJECT:$TAG"
docker build -t "$PROJECT:$TAG" "$REPO_ROOT"
log "Built $PROJECT:$TAG"
