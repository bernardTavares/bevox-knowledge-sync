#!/usr/bin/env bash
# git-ops.sh - safe git wrappers for the clone

# Roda git no clone
ks_git() {
  git -C "$KS_CLONE_PATH" "$@"
}

# Branch atual
ks_git_branch() {
  ks_git symbolic-ref --short HEAD 2>/dev/null || echo ""
}

# HEAD detached?
ks_git_detached() {
  if ks_git symbolic-ref -q HEAD >/dev/null 2>&1; then
    echo "false"
  else
    echo "true"
  fi
}

# SHA do HEAD
ks_git_head_sha() {
  ks_git rev-parse HEAD 2>/dev/null || echo ""
}

# SHA do tracking branch
ks_git_tracking_sha() {
  local tracking
  tracking="$(ks_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "")"
  if [[ -n "$tracking" ]]; then
    ks_git rev-parse "$tracking" 2>/dev/null || echo ""
  fi
}

# Tracking branch name (ex: origin/main)
ks_git_tracking_name() {
  ks_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo ""
}

# Ahead/behind counts: retorna "ahead behind"
ks_git_ahead_behind() {
  local tracking
  tracking="$(ks_git_tracking_name)"
  if [[ -z "$tracking" ]]; then
    echo "0 0"
    return
  fi
  ks_git rev-list --left-right --count "${tracking}...HEAD" 2>/dev/null | awk '{print $2, $1}'
}

# Working tree clean?
ks_git_clean() {
  if [[ -z "$(ks_git status --porcelain 2>/dev/null)" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Listas de arquivos modificados/untracked/staged como JSON arrays
ks_git_modified_json() {
  ks_git status --porcelain 2>/dev/null | awk '/^.M /{print $2}/^M.|^MM/{print $2}' | jq -R . | jq -sc .
}

ks_git_untracked_json() {
  ks_git status --porcelain 2>/dev/null | awk '/^\?\?/{print $2}' | jq -R . | jq -sc .
}

ks_git_staged_json() {
  ks_git status --porcelain 2>/dev/null | awk '/^[AM]./{print $2}' | jq -R . | jq -sc .
}

# Operacoes git em progresso
ks_git_merge_in_progress() {
  [[ -f "$KS_CLONE_PATH/.git/MERGE_HEAD" ]] && echo "true" || echo "false"
}

ks_git_rebase_in_progress() {
  if [[ -d "$KS_CLONE_PATH/.git/rebase-merge" ]] || [[ -d "$KS_CLONE_PATH/.git/rebase-apply" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

ks_git_cherry_pick_in_progress() {
  [[ -f "$KS_CLONE_PATH/.git/CHERRY_PICK_HEAD" ]] && echo "true" || echo "false"
}

# Lista de branches draft/* como JSON
ks_git_draft_branches_json() {
  local branches
  branches="$(ks_git branch --list 'draft/*' 2>/dev/null | sed 's/^[* ] //' | sed 's/^ *//')"
  if [[ -z "$branches" ]]; then
    echo "[]"
    return
  fi
  local result="[]"
  while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    local sha
    sha="$(ks_git rev-parse "$br" 2>/dev/null || echo "")"
    local main_sha
    main_sha="$(ks_git rev-parse main 2>/dev/null || echo "")"
    local ahead_main="0"
    if [[ -n "$sha" && -n "$main_sha" ]]; then
      ahead_main="$(ks_git rev-list --count "main..$br" 2>/dev/null || echo "0")"
    fi
    result="$(echo "$result" | jq -c \
      --arg name "$br" \
      --arg sha "$sha" \
      --argjson ahead "$ahead_main" \
      '. + [{name: $name, head_sha: $sha, ahead_of_main: $ahead}]')"
  done <<< "$branches"
  echo "$result"
}

# Remote URL
ks_git_remote_url() {
  ks_git config --get remote.origin.url 2>/dev/null || echo ""
}

# Fetch silencioso (retorna 0 ok, 1 erro)
ks_git_fetch_quiet() {
  ks_git fetch --quiet origin 2>&1
}
