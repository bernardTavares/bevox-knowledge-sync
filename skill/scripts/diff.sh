#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/git-ops.sh"

if [[ $# -gt 0 ]]; then
  ks_git diff -- "$@"
else
  ks_git diff
fi
