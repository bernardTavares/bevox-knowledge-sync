#!/usr/bin/env bash
# health - resumo de health.overall + issues
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"

if [[ "${1:-}" == "--json" ]]; then
  ks_state_read | jq '.health'
  exit 0
fi

state="$(ks_state_read)"
overall="$(echo "$state" | jq -r '.health.overall // "unknown"')"
echo "Overall: $overall"
echo ""
echo "Issues:"
echo "$state" | jq -r '.health.issues[]? | "  [\(.severity)] \(.code) (since \(.since))"' || echo "  (none)"
