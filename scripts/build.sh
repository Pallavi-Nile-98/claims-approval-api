#!/usr/bin/env bash
# Build the Docker image, tagged with the current git commit SHA.
# Usage: bash scripts/build.sh
source "$(dirname "$0")/common.sh"

require_tools git docker
require_clean_tree

TAG=$(image_tag)
log "Building $PROJECT:$TAG"
docker build -t "$PROJECT:$TAG" "$REPO_ROOT"
log "Built $PROJECT:$TAG"
