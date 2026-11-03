#!/usr/bin/env bash
# fetch - forca git fetch e roda Watcher
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/git-ops.sh"
source "$SKILL_DIR/lib/watcher.sh"

ks_check_deps
ks_check_clone
ks_lock 30 || exit 1
trap 'ks_unlock' EXIT

ks_event_append "action_started" '{"action": "fetch"}'
ks_watcher_run fetch
fetch_status="$(ks_state_read | jq -r '.last.fetch_status // "unknown"')"
ks_event_append "action_succeeded" "$(jq -nc --arg s "$fetch_status" '{action: "fetch", fetch_status: $s}')"

exec "$SKILL_DIR/scripts/status.sh"
