#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/events.sh"

n=20
while [[ $# -gt 0 ]]; do
  case "$1" in
    --last) n="$2"; shift 2 ;;
    --json) shift ;;
    *) echo "events: arg desconhecido: $1" >&2; exit 2 ;;
  esac
done

ks_events_tail "$n" | jq -c .
