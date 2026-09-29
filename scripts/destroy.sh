#!/usr/bin/env bash
# Delete every AWS resource this project created, then confirm nothing billable is left.
# Usage: bash scripts/destroy.sh
source "$(dirname "$0")/common.sh"

require_tools git aws terraform
require_aws_credentials

tf_init
log "This deletes EVERYTHING, including the database and all of its data."
log "Review the plan, then type 'yes'. (Takes ~5-10 minutes, mostly deleting RDS.)"
tf_run destroy

bash "$SCRIPT_DIR/check-leftovers.sh"
