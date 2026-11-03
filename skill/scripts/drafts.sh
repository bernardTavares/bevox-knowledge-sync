#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"

if [[ "${1:-}" == "--json" ]]; then
  ks_state_read | jq '.draft_branches'
  exit 0
fi

drafts="$(ks_state_read | jq -c '.draft_branches')"
count="$(echo "$drafts" | jq 'length')"
echo "Drafts: $count active"
echo "$drafts" | jq -r '.[] | "  - \(.name)  head=\(.head_sha[0:10])  ahead_of_main=\(.ahead_of_main)"'
