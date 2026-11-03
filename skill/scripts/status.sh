#!/usr/bin/env bash
# status - leitura pura do state.json (geral) OU estado de approval especifico
# Modo geral: knowledge-sync status [--json]
# Modo especifico: knowledge-sync status <ref> [--json]
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/approval.sh"

JSON_MODE=false
REF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=true; shift ;;
    *) REF="$1"; shift ;;
  esac
done

# ========================================
# Modo especifico: status <ref>
# ========================================
if [[ -n "$REF" ]]; then
  # Resolver referencia para approval_id (mas tratar erros como output, nao falha)
  resolved=""
  state="not_found"
  raw_id=""

  if [[ "$REF" == "last" ]]; then
    # Para "last", pega o pending mais recente que ainda existe (qualquer estado)
    raw_id="$(jq -rc 'select(.event=="canonical_approval_pending") | .payload.approval_id' "$KS_EVENTS_FILE" 2>/dev/null | tail -1)"
  else
    # Prefix matching contra TODOS os approval_ids vistos
    if [[ ${#REF} -ge 8 ]]; then
      all_ids="$(jq -rc 'select(.event=="canonical_approval_pending") | .payload.approval_id' "$KS_EVENTS_FILE" 2>/dev/null | sort -u)"
      matches="$(echo "$all_ids" | grep "^${REF}" || true)"
      match_count="$(echo "$matches" | grep -c '^' 2>/dev/null || echo 0)"
      [[ -z "$matches" ]] && match_count=0
      if (( match_count == 1 )); then
        raw_id="$matches"
      fi
    fi
  fi

  # Initialize defaults (used even in not_found path for JSON mode)
  action=""
  pending_ts=""
  context_json="{}"
  age_seconds=0
  ttl_remaining=0

  if [[ -z "$raw_id" ]]; then
    state="not_found"
  else
    # Verificar estado
    has_executed="$(jq -rc --arg id "$raw_id" 'select((.event=="canonical_committed" or .event=="canonical_pushed" or .event=="canonical_marker_created") and .payload.approval_id == $id)' "$KS_EVENTS_FILE" 2>/dev/null | head -1)"
    has_rejected="$(jq -rc --arg id "$raw_id" 'select(.event=="canonical_approval_rejected" and .payload.approval_id == $id)' "$KS_EVENTS_FILE" 2>/dev/null | head -1)"
    has_granted="$(jq -rc --arg id "$raw_id" 'select(.event=="canonical_approval_granted" and .payload.approval_id == $id)' "$KS_EVENTS_FILE" 2>/dev/null | head -1)"

    pending_event="$(jq -rc --arg id "$raw_id" 'select(.event=="canonical_approval_pending" and .payload.approval_id == $id)' "$KS_EVENTS_FILE" 2>/dev/null | head -1)"
    pending_ts="$(echo "$pending_event" | jq -r '.ts' 2>/dev/null || echo "")"
    action="$(echo "$pending_event" | jq -r '.payload.action' 2>/dev/null || echo "")"
    context_json="$(echo "$pending_event" | jq -c '.payload.context' 2>/dev/null || echo "{}")"

    now_epoch="$(date -u +%s)"
    pending_epoch="$(date -u -d "$pending_ts" +%s 2>/dev/null || echo 0)"
    age_seconds=$((now_epoch - pending_epoch))
    ttl_remaining=$((KS_APPROVAL_TTL_SECONDS - age_seconds))

    if [[ -n "$has_executed" ]]; then
      state="executed"
    elif [[ -n "$has_rejected" ]]; then
      state="rejected"
    elif (( age_seconds > KS_APPROVAL_TTL_SECONDS )); then
      state="expired"
    elif [[ -n "$has_granted" ]]; then
      state="granted"
    else
      state="pending"
    fi
  fi

  if $JSON_MODE; then
    jq -nc \
      --arg id "$raw_id" \
      --arg short "${raw_id:0:8}" \
      --arg state "$state" \
      --arg action "$action" \
      --argjson context "$context_json" \
      --arg created_at "$pending_ts" \
      --argjson age "${age_seconds:-0}" \
      --argjson ttl_remaining "${ttl_remaining:-0}" \
      '{
        approval_id: (if $id == "" then null else $id end),
        short_id: (if $short == "" then null else $short end),
        state: $state,
        action: (if $action == "" or $action == "null" then null else $action end),
        context: $context,
        created_at: (if $created_at == "" then null else $created_at end),
        age_seconds: $age,
        ttl_remaining_seconds: $ttl_remaining
      }'
    exit 0
  fi

  # Saida humana especifica
  if [[ "$state" == "not_found" ]]; then
    echo "Approval $REF: nao encontrado"
    exit 0
  fi

  echo "Approval ${raw_id:0:8}"
  echo "Estado: $state"
  [[ -n "$action" && "$action" != "null" ]] && echo "Action: $action"
  if [[ -n "$pending_ts" ]]; then
    age_min=$((age_seconds / 60))
    echo "Criado: $pending_ts (ha ${age_min} min)"
  fi
  if [[ "$state" == "pending" || "$state" == "granted" ]] && (( ttl_remaining > 0 )); then
    ttl_min=$((ttl_remaining / 60))
    echo "TTL restante: ${ttl_min} min"
  fi
  exit 0
fi

# ========================================
# Modo geral: status (sem ref)
# ========================================
if [[ "$JSON_MODE" == "true" ]]; then
  ks_state_read
  exit 0
fi

state="$(ks_state_read)"
if [[ "$state" == "{}" || -z "$state" ]]; then
  echo "knowledge-sync - state vazio. Rode 'knowledge-sync refresh' primeiro."
  exit 0
fi

cat <<HEAD
knowledge-sync - bevox-knowledge

  Branch:           $(echo "$state" | jq -r '.branch.current // "?"')
  Tracking:         $(echo "$state" | jq -r '.branch.tracking // "?"')
  Head:             $(echo "$state" | jq -r '.branch.head_sha // "?" | .[0:10]')
  Remote head:      $(echo "$state" | jq -r '.branch.tracking_head_sha // "?" | .[0:10]')
  Sync:             ahead $(echo "$state" | jq -r '.branch.ahead'), behind $(echo "$state" | jq -r '.branch.behind')
  Working tree:     $(echo "$state" | jq -r 'if .working_tree.clean then "clean" else "dirty" end')
  Git operations:   $(echo "$state" | jq -r 'if (.git_operations.merge_in_progress or .git_operations.rebase_in_progress or .git_operations.cherry_pick_in_progress) then "in progress" else "none" end')
  Conflicts:        $(echo "$state" | jq -r 'if .conflicts.potential then "POTENTIAL: \(.conflicts.reason // "")" else "none" end')

  Drafts:           $(echo "$state" | jq -r '.draft_branches | length') active
HEAD

echo "$state" | jq -r '.draft_branches[]? | "    - \(.name)  (head \(.head_sha[0:10]), \(.ahead_of_main) ahead of main)"'

cat <<TAIL

  Health:           $(echo "$state" | jq -r '.health.overall' | tr 'a-z' 'A-Z')
TAIL

echo "$state" | jq -r '.health.issues[]? | "    - \(.code) [\(.severity)] since \(.since)"'

cat <<TIME

  Last fetch:       $(echo "$state" | jq -r '.last.fetch_at // "never"')
  Last commit:      $(echo "$state" | jq -r '.last.commit_at // "never"') ($(echo "$state" | jq -r '.last.commit_sha // "?"'))
  Last push:        $(echo "$state" | jq -r '.last.push_at // "never"')
  Watcher last ran: $(echo "$state" | jq -r '.watcher.ran_at // "never"') ($(echo "$state" | jq -r '.watcher.duration_ms // 0')ms)
TIME
