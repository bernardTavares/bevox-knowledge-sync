#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/git-ops.sh"

n=10
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) n="$2"; shift 2 ;;
    *) shift ;;
  esac
done

ks_git log --oneline -n "$n"
