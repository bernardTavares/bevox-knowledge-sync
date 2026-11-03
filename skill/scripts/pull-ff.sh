#!/usr/bin/env bash
# pull-ff - git pull --ff-only com guardrails
# Recusa se: dirty, op git pendente, ahead > 0, tracking inconsistente, conflito potencial
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

# Refrescar Watcher antes
ks_watcher_run

# Validacoes (preconditions per contrato)
state="$(ks_state_read)"
clean="$(echo "$state" | jq -r '.working_tree.clean')"
ahead="$(echo "$state" | jq -r '.branch.ahead')"
behind="$(echo "$state" | jq -r '.branch.behind')"
tracking="$(echo "$state" | jq -r '.branch.tracking // ""')"
merge_in="$(echo "$state" | jq -r '.git_operations.merge_in_progress')"
rebase_in="$(echo "$state" | jq -r '.git_operations.rebase_in_progress')"
cherry_in="$(echo "$state" | jq -r '.git_operations.cherry_pick_in_progress')"
conflict="$(echo "$state" | jq -r '.conflicts.potential')"

reason=""
if [[ "$clean" != "true" ]]; then
  reason="working tree not clean"
elif [[ "$merge_in" == "true" || "$rebase_in" == "true" || "$cherry_in" == "true" ]]; then
  reason="git operation in progress"
elif (( ahead > 0 )); then
  reason="non-ff: would require merge (ahead $ahead)"
elif [[ -z "$tracking" || "$tracking" == "null" ]]; then
  reason="tracking inconsistent"
elif [[ "$conflict" == "true" ]]; then
  reason="potential conflict"
fi

if [[ -n "$reason" ]]; then
  ks_event_append "action_rejected" "$(jq -nc --arg r "$reason" '{action: "pull-ff", reason: $r}')"
  echo "BLOCKED: $reason" >&2
  exit 3
fi

# Se behind == 0, no-op
if (( behind == 0 )); then
  echo "already up to date"
  ks_event_append "action_succeeded" '{"action": "pull-ff", "noop": true}'
  exit 0
fi

ks_event_append "action_started" '{"action": "pull-ff"}'

# Tentar pull --ff-only
if ks_git pull --ff-only --quiet 2>&1; then
  ks_watcher_run
  ks_event_append "action_succeeded" "$(jq -nc \
    --arg sha "$(ks_git_head_sha)" \
    '{action: "pull-ff", new_head_sha: $sha}')"
  echo "OK"
else
  ks_event_append "action_failed" '{"action": "pull-ff", "error": "git pull --ff-only failed"}'
  echo "FAILED" >&2
  exit 1
fi
