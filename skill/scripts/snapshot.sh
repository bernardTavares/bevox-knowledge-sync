#!/usr/bin/env bash
# snapshot - subcomandos: create, verify
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/git-ops.sh"
source "$SKILL_DIR/lib/snapshot.sh"

ks_check_deps
ks_check_clone

sub="${1:-}"; shift || true

case "$sub" in
  create)
    type="auto-hourly"
    slug=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --manual) type="manual"; slug="$2"; shift 2 ;;
        --auto) type="auto-hourly"; shift ;;
        --pre-canonical) type="pre-canonical"; slug="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    ks_lock 30 || exit 1
    trap 'ks_unlock' EXIT
    path="$(ks_snapshot_create "$type" "$slug")"
    ks_event_append "snapshot_created" "$(jq -nc --arg t "$type" --arg p "$path" '{type: $t, path: $p}')"
    ks_snapshot_rotate
    echo "$path"
    ;;

  verify)
    sample_n=0
    verify_all=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all) verify_all=true; shift ;;
        --sample) sample_n="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    [[ ! -f "$KS_SNAPSHOTS_INDEX" ]] && { echo "no index"; exit 0; }

    if $verify_all; then
      mapfile -t entries < "$KS_SNAPSHOTS_INDEX"
    else
      [[ "$sample_n" -eq 0 ]] && sample_n=3
      mapfile -t entries < <(shuf "$KS_SNAPSHOTS_INDEX" 2>/dev/null | head -n "$sample_n")
    fi

    failed=0
    verified=0
    for entry in "${entries[@]}"; do
      rel_path="$(echo "$entry" | jq -r '.path')"
      sha="$(echo "$entry" | jq -r '.sha256')"
      full_path="$KS_SNAPSHOTS_DIR/$rel_path"
      if ks_snapshot_verify_one "$full_path" "$sha"; then
        ks_snapshot_mark_verified "$rel_path" "verified"
        verified=$((verified+1))
      else
        ks_snapshot_mark_verified "$rel_path" "failed"
        failed=$((failed+1))
        ks_event_append "snapshot_verification_failed" "$(jq -nc --arg p "$rel_path" '{path: $p}')"
      fi
    done

    echo "verified=$verified failed=$failed"
    [[ $failed -gt 0 ]] && exit 1
    exit 0
    ;;

  *)
    echo "snapshot: subcomando desconhecido: $sub" >&2
    echo "Use: snapshot create [--manual <slug>] | snapshot verify [--all|--sample N]" >&2
    exit 2 ;;
esac
