#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"

type_filter=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) type_filter="$2"; shift 2 ;;
    --json) shift ;;
    *) shift ;;
  esac
done

if [[ ! -f "$KS_SNAPSHOTS_INDEX" ]]; then
  echo "(nenhum snapshot)"
  exit 0
fi

if [[ -z "$type_filter" ]]; then
  cat "$KS_SNAPSHOTS_INDEX" | jq -c .
else
  grep -F "\"type\":\"$type_filter\"" "$KS_SNAPSHOTS_INDEX" | jq -c .
fi
