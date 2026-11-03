#!/usr/bin/env bash
# pending - lista approvals canonicos pendentes
# Output: humano (default) ou JSON (--json)
# Ordem: FIFO (mais antigo primeiro)
# Limit: 10
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/approval.sh"

LIMIT=10
JSON_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=true; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ ! -f "$KS_EVENTS_FILE" ]]; then
  if $JSON_MODE; then
    echo '{"count": 0, "total": 0, "limit": '"$LIMIT"', "items": []}'
  else
    echo "Sem approvals pendentes."
  fi
  exit 0
fi

# Identificar approvals pending: tem canonical_approval_pending, sem granted/rejected/executed depois
# Tambem filtrar expirados (TTL excedido)
now_epoch="$(date -u +%s)"

# Coletar todos os approval_ids ainda pending (com card v2)
pending_data="$(jq -rc --argjson now "$now_epoch" --argjson ttl "$KS_APPROVAL_TTL_SECONDS" '
  select(.event=="canonical_approval_pending")
  | {
      approval_id: .payload.approval_id,
      action: .payload.action,
      context: .payload.context,
      card: (.payload.card // null),
      created_at: .ts,
      created_epoch: (.ts | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)
    }
  | select(($now - .created_epoch) <= $ttl)
' "$KS_EVENTS_FILE" 2>/dev/null)"

if [[ -z "$pending_data" ]]; then
  if $JSON_MODE; then
    echo '{"count": 0, "total": 0, "limit": '"$LIMIT"', "items": []}'
  else
    echo "Sem approvals pendentes."
  fi
  exit 0
fi

# Filtrar os que ja foram resolvidos (granted/rejected/executed)
resolved_ids="$(jq -rc 'select(.event=="canonical_approval_granted" or .event=="canonical_approval_rejected" or .event=="canonical_committed" or .event=="canonical_pushed" or .event=="canonical_marker_created") | .payload.approval_id // empty' "$KS_EVENTS_FILE" 2>/dev/null | sort -u)"

# Construir lista de pendentes ainda nao resolvidos, ordenada FIFO
items_json="$(echo "$pending_data" | jq -sc --argjson now "$now_epoch" --arg resolved "$resolved_ids" '
  . as $all
  | ($resolved | split("\n")) as $resolved_list
  | [
      $all[]
      | select(.approval_id as $id | $resolved_list | index($id) | not)
      | {
          approval_id: .approval_id,
          short_id: .approval_id[0:8],
          action: .action,
          context: .context,
          card: .card,
          created_at: .created_at,
          age_seconds: ($now - .created_epoch)
        }
    ]
  | sort_by(.created_at)
')"

total="$(echo "$items_json" | jq 'length')"

# Aplicar limit
visible_items="$(echo "$items_json" | jq -c --argjson n "$LIMIT" '.[:$n]')"
visible_count="$(echo "$visible_items" | jq 'length')"

if $JSON_MODE; then
  jq -nc \
    --argjson count "$visible_count" \
    --argjson total "$total" \
    --argjson limit "$LIMIT" \
    --argjson items "$visible_items" \
    '{count: $count, total: $total, limit: $limit, items: $items}'
  exit 0
fi

# Saida humana
if (( visible_count == 0 )); then
  echo "Sem approvals pendentes."
  exit 0
fi

if (( total > visible_count )); then
  echo "Pendentes ($visible_count de $total) - use o CLI para ver todos:"
else
  echo "Pendentes ($visible_count de $total):"
fi
echo ""

echo "$visible_items" | jq -r '.[] |
  "[\(.short_id)] \(.action)\n" +
  (if .card and .card.summary then "  " + .card.summary + "\n" else "" end) +
  (if .card and .card.risk and .card.risk.level then "  risco: " + (.card.risk.level | ascii_upcase) + "\n" else "" end) +
  "  ha \(if (.age_seconds / 60 | floor) < 1 then "<1 min" elif (.age_seconds / 60 | floor) < 60 then "\(.age_seconds / 60 | floor) min" else "\(.age_seconds / 3600 | floor) h" end)\n"'

echo ""
echo "Use /approve <id-curto> ou /reject <id-curto>"
echo "Detalhes: knowledge-sync status <id-curto>"
