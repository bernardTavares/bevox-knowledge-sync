#!/usr/bin/env bash
# watcher.sh - pure read of clone, derives state.json
# Spec section 3

# Janela minima entre fetches (segundos)
KS_FETCH_MIN_INTERVAL="${KS_FETCH_MIN_INTERVAL:-300}"

# Determina se deve fazer fetch baseado no ultimo fetch
ks_watcher_should_fetch() {
  local last_fetch_at
  last_fetch_at="$(ks_state_read | jq -r '.last.fetch_at // ""')"
  if [[ -z "$last_fetch_at" || "$last_fetch_at" == "null" ]]; then
    echo "true"
    return
  fi
  local last_ts
  last_ts="$(date -u -d "$last_fetch_at" +%s 2>/dev/null || echo 0)"
  local now_ts
  now_ts="$(date -u +%s)"
  local elapsed=$((now_ts - last_ts))
  if (( elapsed >= KS_FETCH_MIN_INTERVAL )); then
    echo "true"
  else
    echo "false"
  fi
}

# Detecao conservadora de conflito potencial
# Retorna "true|false|reason"
# Conservadora: evita merge-tree por ciclo
ks_watcher_conflict_potential() {
  local clean="$1"
  local behind="$2"
  local merge_in="$3"
  local rebase_in="$4"

  # Operacao git em progresso = conflito potencial implicito
  if [[ "$merge_in" == "true" || "$rebase_in" == "true" ]]; then
    echo "true|git operation in progress"
    return
  fi

  # Behind + dirty = risco de conflito ao tentar pull-ff
  if [[ "$behind" -gt 0 && "$clean" == "false" ]]; then
    echo "true|behind remote with dirty working tree"
    return
  fi

  echo "false|"
}

# Calcula health.overall e health.issues
# Retorna JSON do bloco health
ks_watcher_compute_health() {
  local clean="$1"
  local ahead="$2"
  local behind="$3"
  local merge_in="$4"
  local rebase_in="$5"
  local cherry_pick_in="$6"
  local conflict_potential="$7"
  local conflict_reason="$8"

  local previous_state
  previous_state="$(ks_state_read_previous)"

  local now
  now="$(ks_now)"
  local issues="[]"

  # working_tree_dirty
  if [[ "$clean" == "false" ]]; then
    local since
    since="$(echo "$previous_state" | jq -r '.health.issues[]? | select(.code=="working_tree_dirty") | .since' 2>/dev/null | head -1)"
    [[ -z "$since" || "$since" == "null" ]] && since="$now"
    issues="$(echo "$issues" | jq -c \
      --arg since "$since" \
      '. + [{code: "working_tree_dirty", severity: "warn", since: $since, details: {}}]')"
  fi

  # branch_behind
  if [[ "$behind" -gt 0 ]]; then
    local since
    since="$(echo "$previous_state" | jq -r '.health.issues[]? | select(.code=="branch_behind") | .since' 2>/dev/null | head -1)"
    [[ -z "$since" || "$since" == "null" ]] && since="$now"
    issues="$(echo "$issues" | jq -c \
      --arg since "$since" \
      --argjson n "$behind" \
      '. + [{code: "branch_behind", severity: "warn", since: $since, details: {behind: $n}}]')"
  fi

  # branch_ahead
  if [[ "$ahead" -gt 0 ]]; then
    local since
    since="$(echo "$previous_state" | jq -r '.health.issues[]? | select(.code=="branch_ahead") | .since' 2>/dev/null | head -1)"
    [[ -z "$since" || "$since" == "null" ]] && since="$now"
    # Severity: info default, warn after 24h
    local severity="info"
    local since_ts
    since_ts="$(date -u -d "$since" +%s 2>/dev/null || echo 0)"
    local now_ts
    now_ts="$(date -u +%s)"
    if (( now_ts - since_ts >= 86400 )); then
      severity="warn"
    fi
    issues="$(echo "$issues" | jq -c \
      --arg since "$since" \
      --arg sev "$severity" \
      --argjson n "$ahead" \
      '. + [{code: "branch_ahead", severity: $sev, since: $since, details: {ahead: $n}}]')"
  fi

  # git operations
  for op in merge_in_progress:merge rebase_in_progress:rebase cherry_pick_in_progress:cherry_pick; do
    local code="${op%%:*}"
    local val
    case "$code" in
      merge_in_progress) val="$merge_in" ;;
      rebase_in_progress) val="$rebase_in" ;;
      cherry_pick_in_progress) val="$cherry_pick_in" ;;
    esac
    if [[ "$val" == "true" ]]; then
      local since
      since="$(echo "$previous_state" | jq -r --arg c "$code" '.health.issues[]? | select(.code==$c) | .since' 2>/dev/null | head -1)"
      [[ -z "$since" || "$since" == "null" ]] && since="$now"
      issues="$(echo "$issues" | jq -c \
        --arg c "$code" --arg since "$since" \
        '. + [{code: $c, severity: "warn", since: $since, details: {}}]')"
    fi
  done

  # conflict_potential
  if [[ "$conflict_potential" == "true" ]]; then
    local since
    since="$(echo "$previous_state" | jq -r '.health.issues[]? | select(.code=="conflict_potential") | .since' 2>/dev/null | head -1)"
    [[ -z "$since" || "$since" == "null" ]] && since="$now"
    issues="$(echo "$issues" | jq -c \
      --arg since "$since" \
      --arg reason "$conflict_reason" \
      '. + [{code: "conflict_potential", severity: "error", since: $since, details: {reason: $reason}}]')"
  fi

  # Calcular overall
  local overall="ok"
  if echo "$issues" | jq -e '.[] | select(.severity=="error")' >/dev/null 2>&1; then
    overall="critical"
  elif echo "$issues" | jq -e '.[] | select(.severity=="warn")' >/dev/null 2>&1; then
    overall="degraded"
  fi

  jq -nc \
    --arg overall "$overall" \
    --argjson issues "$issues" \
    '{overall: $overall, issues: $issues}'
}

# Roda 1 ciclo do Watcher
# Param: $1 = "fetch" para forcar fetch, "" para respeitar interval
ks_watcher_run() {
  local force_fetch="${1:-}"
  local started_at
  started_at="$(ks_now)"
  local errors="[]"
  local fetch_status="skipped"

  # 1. Fetch (se janela permitir ou forcado)
  local should_fetch
  should_fetch="$(ks_watcher_should_fetch)"
  if [[ "$force_fetch" == "fetch" || "$should_fetch" == "true" ]]; then
    local fetch_output
    if fetch_output="$(ks_git_fetch_quiet 2>&1)"; then
      fetch_status="ok"
    else
      fetch_status="failed"
      local err_summary
      err_summary="$(echo "$fetch_output" | head -3 | tr '\n' ' ' | head -c 200)"
      errors="$(echo "$errors" | jq -c \
        --arg step "git_fetch" \
        --arg cmd "git fetch --quiet origin" \
        --arg stderr "$err_summary" \
        --arg at "$(ks_now)" \
        '. + [{step: $step, command: $cmd, exit_code: 1, stderr_summary: $stderr, occurred_at: $at}]')"
    fi
  fi

  # 2. Coletar info do git
  local branch head_sha tracking tracking_sha detached ahead behind clean
  branch="$(ks_git_branch)"
  head_sha="$(ks_git_head_sha)"
  tracking="$(ks_git_tracking_name)"
  tracking_sha="$(ks_git_tracking_sha)"
  detached="$(ks_git_detached)"
  read -r ahead behind <<< "$(ks_git_ahead_behind)"

  # Garantir que ahead/behind sao numericos
  ahead="${ahead:-0}"
  behind="${behind:-0}"
  # Se retornou so um valor, ou vazio, defaultar
  [[ "$ahead" =~ ^[0-9]+$ ]] || ahead=0
  [[ "$behind" =~ ^[0-9]+$ ]] || behind=0

  clean="$(ks_git_clean)"

  # 3. Working tree details
  local modified_json untracked_json staged_json
  modified_json="$(ks_git_modified_json)"
  untracked_json="$(ks_git_untracked_json)"
  staged_json="$(ks_git_staged_json)"

  # 4. Git operations em progresso
  local merge_in rebase_in cherry_pick_in
  merge_in="$(ks_git_merge_in_progress)"
  rebase_in="$(ks_git_rebase_in_progress)"
  cherry_pick_in="$(ks_git_cherry_pick_in_progress)"

  # 5. Conflict detection conservadora
  local conflict_result
  conflict_result="$(ks_watcher_conflict_potential "$clean" "$behind" "$merge_in" "$rebase_in")"
  local conflict_potential="${conflict_result%%|*}"
  local conflict_reason="${conflict_result##*|}"

  # 6. Drafts
  local drafts_json
  drafts_json="$(ks_git_draft_branches_json)"

  # 7. Health
  local health_json
  health_json="$(ks_watcher_compute_health "$clean" "$ahead" "$behind" "$merge_in" "$rebase_in" "$cherry_pick_in" "$conflict_potential" "$conflict_reason")"

  # 8. Last fields - preserva o que ja tem
  local last_pull_at last_pull_status last_commit_at last_commit_sha last_push_at last_push_status
  local previous
  previous="$(ks_state_read)"
  last_pull_at="$(echo "$previous" | jq -r '.last.pull_at // ""')"
  last_pull_status="$(echo "$previous" | jq -r '.last.pull_status // ""')"
  last_commit_at="$(echo "$previous" | jq -r '.last.commit_at // ""')"
  last_commit_sha="$(echo "$previous" | jq -r '.last.commit_sha // ""')"
  last_push_at="$(echo "$previous" | jq -r '.last.push_at // ""')"
  last_push_status="$(echo "$previous" | jq -r '.last.push_status // ""')"

  local last_fetch_at
  if [[ "$fetch_status" == "ok" ]]; then
    last_fetch_at="$started_at"
  else
    last_fetch_at="$(echo "$previous" | jq -r '.last.fetch_at // ""')"
  fi

  # 9. Duracao
  local finished_at
  finished_at="$(ks_now)"
  local duration_ms=0
  local started_ts finished_ts
  started_ts="$(date -u -d "$started_at" +%s%3N 2>/dev/null || echo 0)"
  finished_ts="$(date -u -d "$finished_at" +%s%3N 2>/dev/null || echo 0)"
  if (( finished_ts > started_ts )); then
    duration_ms=$((finished_ts - started_ts))
  fi

  # 10. Build state JSON
  local state_json
  state_json="$(jq -nc \
    --arg observed_at "$started_at" \
    --arg clone_path "$KS_CLONE_PATH" \
    --arg remote_url "$(ks_git_remote_url)" \
    --arg branch "$branch" \
    --arg tracking "$tracking" \
    --arg head_sha "$head_sha" \
    --arg tracking_sha "$tracking_sha" \
    --argjson detached "$detached" \
    --argjson ahead "$ahead" \
    --argjson behind "$behind" \
    --argjson clean "$clean" \
    --argjson modified "$modified_json" \
    --argjson untracked "$untracked_json" \
    --argjson staged "$staged_json" \
    --argjson merge_in "$merge_in" \
    --argjson rebase_in "$rebase_in" \
    --argjson cherry_in "$cherry_pick_in" \
    --argjson conflict "$conflict_potential" \
    --arg conflict_reason "$conflict_reason" \
    --argjson drafts "$drafts_json" \
    --arg last_fetch_at "$last_fetch_at" \
    --arg fetch_status "$fetch_status" \
    --arg last_pull_at "$last_pull_at" \
    --arg last_pull_status "$last_pull_status" \
    --arg last_commit_at "$last_commit_at" \
    --arg last_commit_sha "$last_commit_sha" \
    --arg last_push_at "$last_push_at" \
    --arg last_push_status "$last_push_status" \
    --argjson health "$health_json" \
    --arg ran_at "$started_at" \
    --argjson duration_ms "$duration_ms" \
    --argjson errors "$errors" \
    '{
      version: 1,
      observed_at: $observed_at,
      clone_path: $clone_path,
      remote: {name: "origin", url: $remote_url},
      branch: {
        current: $branch,
        tracking: $tracking,
        head_sha: $head_sha,
        tracking_head_sha: $tracking_sha,
        detached: $detached,
        ahead: $ahead,
        behind: $behind
      },
      working_tree: {
        clean: $clean,
        modified: $modified,
        untracked: $untracked,
        staged: $staged
      },
      git_operations: {
        merge_in_progress: $merge_in,
        rebase_in_progress: $rebase_in,
        cherry_pick_in_progress: $cherry_in
      },
      conflicts: {
        potential: $conflict,
        files: [],
        reason: (if $conflict_reason == "" then null else $conflict_reason end)
      },
      draft_branches: $drafts,
      last: {
        fetch_at: (if $last_fetch_at == "" then null else $last_fetch_at end),
        fetch_status: (if $fetch_status == "skipped" then $last_pull_status else $fetch_status end),
        pull_at: (if $last_pull_at == "" then null else $last_pull_at end),
        pull_status: (if $last_pull_status == "" then null else $last_pull_status end),
        commit_at: (if $last_commit_at == "" then null else $last_commit_at end),
        commit_sha: (if $last_commit_sha == "" then null else $last_commit_sha end),
        push_at: (if $last_push_at == "" then null else $last_push_at end),
        push_status: (if $last_push_status == "" then null else $last_push_status end)
      },
      health: $health,
      watcher: {
        ran_at: $ran_at,
        duration_ms: $duration_ms,
        errors: $errors
      }
    }')"

  echo "$state_json" | ks_state_write

  ks_event_append "watcher_ran" "$(jq -nc \
    --argjson ms "$duration_ms" \
    --argjson errors "$errors" \
    '{duration_ms: $ms, errors: $errors}')"
}

# Detecta mudancas relevantes entre state.previous e state e dispara notificacoes
# Chamado APOS o ks_watcher_run principal
ks_watcher_dispatch_notifications() {
  source "$SKILL_DIR/lib/notify.sh"

  local current previous
  current="$(ks_state_read)"
  previous="$(ks_state_read_previous)"

  # working_tree_dirty - com janela de quietude
  local cur_clean prev_clean cur_dirty_since
  cur_clean="$(echo "$current" | jq -r '.working_tree.clean')"
  # Note: jq `false // true` evaluates to `true`, so we use explicit null check
  prev_clean="$(echo "$previous" | jq -r 'if .working_tree.clean == null then "true" else (.working_tree.clean | tostring) end')"
  cur_dirty_since="$(echo "$current" | jq -r '.health.issues[]? | select(.code=="working_tree_dirty") | .since' | head -1)"

  if [[ "$cur_clean" == "false" && "$prev_clean" == "true" ]]; then
    # Acabou de virar dirty - aguardar janela de quietude antes de notificar
    # Registra evento; a notificacao real acontece no proximo ciclo se ainda dirty
    ks_event_append "working_tree_dirty_observed" "$(jq -nc --arg s "$cur_dirty_since" '{since: $s}')"
  elif [[ "$cur_clean" == "false" && "$prev_clean" == "false" ]]; then
    # Continua dirty - verificar se passou a janela de quietude
    local since_ts now_ts elapsed
    since_ts="$(date -u -d "$cur_dirty_since" +%s 2>/dev/null || echo 0)"
    now_ts="$(date -u +%s)"
    elapsed=$((now_ts - since_ts))
    if (( elapsed >= KS_NOTIFY_DIRTY_QUIET_WINDOW )); then
      local files
      files="$(echo "$current" | jq -r '[.working_tree.modified[], .working_tree.untracked[], .working_tree.staged[]] | join(", ")')"
      local file_hash
      file_hash="$(echo "$files" | sha256sum | awk '{print $1}' | head -c 12)"
      local msg
      msg="$(ks_notify_format_message \
        "working_tree_dirty" "warn" \
        "Working tree dirty - mudancas nao commitadas" \
        "Branch: $(echo "$current" | jq -r '.branch.current')\nArquivos: $files" \
        "$cur_dirty_since (ha $((elapsed/60))min)" \
        "Commitar em draft branch ou descartar" \
        "/knowledge-sync draft create <slug>\n/knowledge-sync diff")"
      ks_notify_dispatch "working_tree_dirty" "warn" "$msg" "$file_hash"
    fi
  elif [[ "$cur_clean" == "true" && "$prev_clean" == "false" ]]; then
    # Resolveu - info, so registra
    ks_event_append "working_tree_clean" '{}'
  fi

  # branch_behind
  local cur_behind prev_behind
  cur_behind="$(echo "$current" | jq -r '.branch.behind')"
  prev_behind="$(echo "$previous" | jq -r '.branch.behind // 0')"
  if (( cur_behind > 0 )) && (( prev_behind == 0 )); then
    local msg
    msg="$(ks_notify_format_message \
      "branch_behind" "warn" \
      "Branch local esta atras do remote ($cur_behind commits)" \
      "Voce vai precisar fazer pull-ff para sincronizar" \
      "agora" \
      "Rodar pull-ff (so se working tree estiver clean)" \
      "/knowledge-sync pull-ff")"
    ks_notify_dispatch "branch_behind" "warn" "$msg"
  fi

  # branch_synced
  local cur_ahead prev_ahead
  cur_ahead="$(echo "$current" | jq -r '.branch.ahead')"
  prev_ahead="$(echo "$previous" | jq -r '.branch.ahead // 0')"
  if (( cur_ahead == 0 )) && (( cur_behind == 0 )) && (( prev_ahead != 0 || prev_behind != 0 )); then
    ks_event_append "branch_synced" '{}'
  fi

  # conflict_potential
  local cur_conflict prev_conflict
  cur_conflict="$(echo "$current" | jq -r '.conflicts.potential')"
  # Note: jq `false // false` evaluates to `false` (correct), but using explicit check for safety
  prev_conflict="$(echo "$previous" | jq -r 'if .conflicts.potential == null then "false" else (.conflicts.potential | tostring) end')"
  if [[ "$cur_conflict" == "true" && "$prev_conflict" == "false" ]]; then
    local reason
    reason="$(echo "$current" | jq -r '.conflicts.reason')"
    local msg
    msg="$(ks_notify_format_message \
      "conflict_potential" "error" \
      "Conflito potencial detectado" \
      "Razao: $reason" \
      "agora" \
      "NAO faca pull. Inspecione manualmente." \
      "/knowledge-sync status\n/knowledge-sync diff")"
    ks_notify_dispatch "conflict_potential" "error" "$msg"
  fi

  # watcher_error
  local errors_count
  errors_count="$(echo "$current" | jq '.watcher.errors | length')"
  if (( errors_count > 0 )); then
    local first_err
    first_err="$(echo "$current" | jq -r '.watcher.errors[0].stderr_summary')"
    local msg
    msg="$(ks_notify_format_message \
      "watcher_error" "error" \
      "Watcher falhou" \
      "$first_err" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "Investigar logs" \
      "/knowledge-sync events --last 10")"
    ks_notify_dispatch "watcher_error" "error" "$msg"
  fi
}
