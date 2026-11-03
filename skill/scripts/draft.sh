#!/usr/bin/env bash
# draft - subcomandos: create, commit, push, delete
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/git-ops.sh"
source "$SKILL_DIR/lib/watcher.sh"

ks_check_deps
ks_check_clone

sub="${1:-}"; shift || true

case "$sub" in
  create)
    slug="${1:-}"
    [[ -z "$slug" ]] && { echo "draft create <slug>" >&2; exit 2; }
    ks_lock 30 || exit 1
    trap 'ks_unlock' EXIT

    branch_name="draft/$slug"
    ks_event_append "action_started" "$(jq -nc --arg b "$branch_name" '{action: "draft create", branch: $b}')"

    if ks_git show-ref --quiet --verify "refs/heads/$branch_name"; then
      ks_event_append "action_rejected" "$(jq -nc --arg b "$branch_name" '{action: "draft create", reason: "branch already exists", branch: $b}')"
      echo "BLOCKED: branch ja existe: $branch_name" >&2
      exit 3
    fi

    ks_git checkout -b "$branch_name" 2>&1
    ks_watcher_run
    ks_event_append "draft_branch_created" "$(jq -nc --arg b "$branch_name" '{branch: $b}')"
    ks_event_append "action_succeeded" "$(jq -nc --arg b "$branch_name" '{action: "draft create", branch: $b}')"
    echo "OK: criado $branch_name"
    ;;

  commit)
    msg=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -m) msg="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -z "$msg" ]] && { echo "draft commit -m <msg>" >&2; exit 2; }

    ks_lock 30 || exit 1
    trap 'ks_unlock' EXIT

    current_branch="$(ks_git_branch)"
    if [[ "$current_branch" != draft/* ]]; then
      ks_event_append "action_rejected" "$(jq -nc --arg b "$current_branch" '{action: "draft commit", reason: "current branch is not draft/*", branch: $b}')"
      echo "BLOCKED: branch atual nao e draft/* (esta em $current_branch)" >&2
      exit 3
    fi

    ks_event_append "action_started" "$(jq -nc --arg b "$current_branch" --arg m "$msg" '{action: "draft commit", branch: $b, message: $m}')"

    ks_git add -A
    if ks_git commit -m "$msg" --quiet 2>&1; then
      new_sha="$(ks_git_head_sha)"
      ks_watcher_run
      ks_event_append "action_succeeded" "$(jq -nc --arg b "$current_branch" --arg s "$new_sha" '{action: "draft commit", branch: $b, new_sha: $s}')"
      echo "OK: commit $new_sha"
    else
      ks_event_append "action_failed" "$(jq -nc --arg b "$current_branch" '{action: "draft commit", branch: $b, error: "commit failed (no changes?)"}')"
      echo "FAILED: commit falhou" >&2
      exit 1
    fi
    ;;

  push)
    ks_lock 30 || exit 1
    trap 'ks_unlock' EXIT

    current_branch="$(ks_git_branch)"
    if [[ "$current_branch" != draft/* ]]; then
      ks_event_append "action_rejected" "$(jq -nc --arg b "$current_branch" '{action: "draft push", reason: "current branch is not draft/*", branch: $b}')"
      echo "BLOCKED: branch atual nao e draft/*" >&2
      exit 3
    fi

    ks_event_append "action_started" "$(jq -nc --arg b "$current_branch" '{action: "draft push", branch: $b}')"

    if ks_git push -u origin "$current_branch" 2>&1; then
      ks_event_append "draft_branch_pushed" "$(jq -nc --arg b "$current_branch" '{branch: $b}')"
      ks_event_append "action_succeeded" "$(jq -nc --arg b "$current_branch" '{action: "draft push", branch: $b}')"
      echo "OK: push $current_branch -> origin"
    else
      ks_event_append "action_failed" "$(jq -nc --arg b "$current_branch" '{action: "draft push", error: "push failed"}')"
      echo "FAILED: push" >&2
      exit 1
    fi
    ;;

  delete)
    name="${1:-}"
    [[ -z "$name" ]] && { echo "draft delete <name>" >&2; exit 2; }
    [[ "$name" != draft/* ]] && name="draft/$name"

    ks_lock 30 || exit 1
    trap 'ks_unlock' EXIT

    if ! ks_git show-ref --quiet --verify "refs/heads/$name"; then
      echo "BLOCKED: branch nao existe localmente: $name" >&2
      exit 3
    fi

    ks_event_append "action_started" "$(jq -nc --arg b "$name" '{action: "draft delete", branch: $b}')"

    # Apaga APENAS local. Branch remota fica.
    if ks_git branch -D "$name" 2>&1; then
      ks_event_append "action_succeeded" "$(jq -nc --arg b "$name" '{action: "draft delete", branch: $b, note: "local only - remote branch (if any) preserved"}')"
      echo "OK: $name apagada localmente. Branch remota correspondente NAO foi apagada."
    else
      ks_event_append "action_failed" "$(jq -nc --arg b "$name" '{action: "draft delete"}')"
      echo "FAILED: delete" >&2
      exit 1
    fi
    ;;

  *)
    echo "draft: subcomando desconhecido: $sub" >&2
    echo "Use: draft create <slug> | draft commit -m <msg> | draft push | draft delete <name>" >&2
    exit 2 ;;
esac
