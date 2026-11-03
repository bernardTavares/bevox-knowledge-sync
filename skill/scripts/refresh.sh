#!/usr/bin/env bash
# refresh (alias: watch) - roda Watcher agora, sem fetch forcado
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

ks_watcher_run
ks_watcher_dispatch_notifications

if [[ "${1:-}" == "--json" ]]; then
  ks_state_read
else
  exec "$SKILL_DIR/scripts/status.sh"
fi
