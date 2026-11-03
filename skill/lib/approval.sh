#!/usr/bin/env bash
# approval.sh - approval flow para acoes canonicas

KS_APPROVAL_TTL_SECONDS="${KS_APPROVAL_TTL_SECONDS:-3600}"  # 1h

# Cria approval request com UUID
# Args: $1 = action_name, $2 = context_json
# Retorna approval_id via stdout
ks_approval_create() {
  local action="$1"
  local context_json="${2:-{\}}"
  local approval_id
  approval_id="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)-${RANDOM}"

  ks_event_append "canonical_approval_pending" "$(jq -nc \
    --arg id "$approval_id" \
    --arg action "$action" \
    --argjson context "$context_json" \
    '{approval_id: $id, action: $action, context: $context}')"

  echo "$approval_id"
}

# Verifica se um approval foi concedido (e nao expirado, e nao usado)
# Args: $1 = approval_id
# Retorna 0 ok, 1 nao
ks_approval_check() {
  local approval_id="$1"

  # Procura granted
  local granted_event
  granted_event="$(grep -F "\"approval_id\":\"$approval_id\"" "$KS_EVENTS_FILE" 2>/dev/null | grep canonical_approval_granted | tail -1)"
  if [[ -z "$granted_event" ]]; then
    return 1
  fi

  # Verifica expiracao
  local granted_at granted_ts now_ts
  granted_at="$(echo "$granted_event" | jq -r '.ts')"
  granted_ts="$(date -u -d "$granted_at" +%s 2>/dev/null || echo 0)"
  now_ts="$(date -u +%s)"
  if (( now_ts - granted_ts > KS_APPROVAL_TTL_SECONDS )); then
    return 1
  fi

  # Verifica se ja foi usado (committed/pushed/marker_created)
  local used
  used="$(grep -F "\"approval_id\":\"$approval_id\"" "$KS_EVENTS_FILE" 2>/dev/null | grep -E "canonical_(committed|pushed|marker_created)" | tail -1)"
  if [[ -n "$used" ]]; then
    return 1
  fi

  return 0
}

# Marca approval como rejeitado
ks_approval_reject() {
  local approval_id="$1"
  local reason="${2:-rejected by user}"
  ks_event_append "canonical_approval_rejected" "$(jq -nc \
    --arg id "$approval_id" --arg r "$reason" \
    '{approval_id: $id, reason: $r}')"
}

# Marca approval como concedido
ks_approval_grant() {
  local approval_id="$1"
  ks_event_append "canonical_approval_granted" "$(jq -nc \
    --arg id "$approval_id" \
    '{approval_id: $id}')"
}

# Resolve uma referencia (last, prefix de 8+ chars, ou UUID completo) para um approval_id real
# Args: $1 = referencia
# Output (se ok): approval_id em stdout, exit 0
# Output (se erro): "ERROR <code>" em stderr, exit != 0
# Codes:
#   not_found            - referencia nao bate com nenhum approval
#   ambiguous:<id1>,<id2>,... - prefix bate com 2+ approvals (em pending)
#   expired:<id>         - bate, mas TTL excedido (granted-stale OU pending-stale)
#   executed:<id>        - bate, mas ja foi executado
#   rejected:<id>        - bate, mas ja foi rejeitado
ks_approval_resolve_reference() {
  local ref="$1"

  if [[ -z "$ref" ]]; then
    echo "ERROR not_found" >&2
    return 1
  fi

  if [[ ! -f "$KS_EVENTS_FILE" ]]; then
    echo "ERROR not_found" >&2
    return 1
  fi

  # Coletar todos os approval_ids ja vistos (qualquer estado)
  local all_pending all_granted all_executed all_rejected
  all_pending="$(jq -rc 'select(.event=="canonical_approval_pending") | {id: .payload.approval_id, ts: .ts}' "$KS_EVENTS_FILE" 2>/dev/null)"
  all_granted="$(jq -rc 'select(.event=="canonical_approval_granted") | .payload.approval_id' "$KS_EVENTS_FILE" 2>/dev/null | sort -u)"
  all_rejected="$(jq -rc 'select(.event=="canonical_approval_rejected") | .payload.approval_id' "$KS_EVENTS_FILE" 2>/dev/null | sort -u)"
  all_executed="$(jq -rc 'select(.event=="canonical_committed" or .event=="canonical_pushed" or .event=="canonical_marker_created") | .payload.approval_id // empty' "$KS_EVENTS_FILE" 2>/dev/null | sort -u)"

  # Determina conjunto de candidatos baseado na referencia
  local candidates
  if [[ "$ref" == "last" ]]; then
    # last = todos os pendentes ainda nao resolvidos (granted/rejected/executed) e nao expirados
    # Filtrar os ja resolvidos para evitar falso-ambiguous
    local all_resolved _now_epoch
    all_resolved="$( (echo "$all_granted"; echo "$all_executed"; echo "$all_rejected") | sort -u | grep -v '^$')"
    _now_epoch="$(date -u +%s)"
    candidates="$(echo "$all_pending" | jq -rc --argjson now "$_now_epoch" --argjson ttl "$KS_APPROVAL_TTL_SECONDS" \
      'select(($now - (.ts | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)) <= $ttl) | .id' | \
      grep -v '^$' | while IFS= read -r cid; do
        echo "$all_resolved" | grep -qx "$cid" || echo "$cid"
      done)"
  else
    # Prefix matching: minimo 8 chars (validado pelo regex no caller, mas defensivo aqui)
    if [[ ${#ref} -lt 8 ]]; then
      echo "ERROR not_found" >&2
      return 1
    fi
    # Match contra approvals em qualquer estado (pending, granted, executed, rejected)
    local all_ids
    all_ids="$( (echo "$all_pending" | jq -rc '.id'; echo "$all_granted"; echo "$all_executed"; echo "$all_rejected") | sort -u | grep -v '^$')"
    candidates="$(echo "$all_ids" | grep "^${ref}" || true)"
  fi

  # Filtrar vazios
  candidates="$(echo "$candidates" | grep -v '^$' || true)"

  # Contar
  local count
  count="$(echo "$candidates" | grep -c '^' 2>/dev/null || echo 0)"
  [[ -z "$candidates" ]] && count=0

  if (( count == 0 )); then
    echo "ERROR not_found" >&2
    return 1
  fi

  if (( count > 1 )); then
    # Ambiguidade: mostrar primeiros 8 chars de cada
    local ids_short
    ids_short="$(echo "$candidates" | head -5 | awk '{print substr($0, 1, 8)}' | tr '\n' ',' | sed 's/,$//')"
    echo "ERROR ambiguous:${ids_short}" >&2
    return 1
  fi

  # 1 unico candidato - verificar estado
  local id="$candidates"

  # Ja executado?
  if echo "$all_executed" | grep -qx "$id"; then
    echo "ERROR executed:${id}" >&2
    return 1
  fi

  # Ja rejeitado?
  if echo "$all_rejected" | grep -qx "$id"; then
    echo "ERROR rejected:${id}" >&2
    return 1
  fi

  # Verificar TTL
  local pending_ts
  pending_ts="$(echo "$all_pending" | jq -rc --arg id "$id" 'select(.id==$id) | .ts' | head -1)"
  if [[ -n "$pending_ts" ]]; then
    local pending_epoch now_epoch elapsed
    pending_epoch="$(date -u -d "$pending_ts" +%s 2>/dev/null || echo 0)"
    now_epoch="$(date -u +%s)"
    elapsed=$((now_epoch - pending_epoch))
    if (( elapsed > KS_APPROVAL_TTL_SECONDS )); then
      echo "ERROR expired:${id}" >&2
      return 1
    fi
  fi

  # Tudo ok - retornar o ID
  echo "$id"
  return 0
}

# =============================================================================
# Approval Card v2 - 6 blocos (spec E1.1 follow-up)
# =============================================================================

# Helper: verifica se um arquivo e um ADR aceito
# Args: $1 = file path relativo ao clone
# Echo: "true" ou "false"
ks_approval_is_accepted_adr() {
  local f="$1"
  # ADRs podem viver em 30_adr/ADR-*.md (pré-ADR-010) ou em subpasta de projeto
  # 30_adr/<_shared|bevox-*|openclaw|company-os>/ADR-*.md (pós-wave-4).
  [[ "$f" =~ ^30_adr/(_shared/|[a-z0-9-]+/)?ADR-[0-9]+.*\.md$ ]] || { echo "false"; return; }
  local full="$KS_CLONE_PATH/$f"
  [[ -f "$full" ]] || { echo "false"; return; }
  if grep -qE '^-?\s*\*\*Status:\*\*\s*aceita' "$full" 2>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}

# Helper: classifica um arquivo quanto ao risco
# Args: $1 = file path relativo
# Echo: "adr-aceita" | "policy" | "core" | "canonical-other" | "inbox" | "draft" | "other"
ks_approval_classify_file() {
  local f="$1"
  case "$f" in
    30_adr/ADR-*.md|30_adr/*/ADR-*.md)
      if [[ "$(ks_approval_is_accepted_adr "$f")" == "true" ]]; then
        echo "adr-aceita"
      else
        echo "canonical-other"
      fi
      ;;
    *policy*|*policies/*)
      echo "policy" ;;
    20_architecture/system-map.md|20_architecture/knowledge-spine.md|20_architecture/_shared/system-map.md|20_architecture/company-os/knowledge-spine.md)
      echo "core" ;;
    00_inbox/*)
      echo "inbox" ;;
    20_architecture/*|10_prd/*|30_adr/*|35_specs/*|40_roadmap/*|50_releases/*|60_customer-feedback/*|70_metrics/*)
      echo "canonical-other" ;;
    *)
      echo "other" ;;
  esac
}

# Helper: prioridade numerica para ordenacao de arquivos por risco
# Maior = mais relevante
ks_approval_file_priority() {
  case "$1" in
    adr-aceita) echo 100 ;;
    policy) echo 90 ;;
    core) echo 80 ;;
    canonical-other) echo 50 ;;
    inbox) echo 20 ;;
    draft) echo 10 ;;
    *) echo 0 ;;
  esac
}

# Escolhe o arquivo "mais relevante" de uma lista para preview de diff
# Args: $@ = lista de files
# Echo: path do arquivo escolhido
ks_approval_pick_most_relevant_file() {
  local best="" best_prio=-1
  for f in "$@"; do
    local class prio
    class="$(ks_approval_classify_file "$f")"
    prio="$(ks_approval_file_priority "$class")"
    if (( prio > best_prio )); then
      best_prio=$prio
      best="$f"
    elif (( prio == best_prio )) && [[ -z "$best" || "$f" < "$best" ]]; then
      best="$f"
    fi
  done
  echo "$best"
}

# Gera diffstat (staged) de uma lista de arquivos
# Args: $@ = lista de arquivos
# Echo: diffstat multiline
ks_approval_diffstat() {
  if [[ $# -eq 0 ]]; then
    ks_git diff --cached --stat 2>/dev/null
  else
    ks_git diff --cached --stat -- "$@" 2>/dev/null
  fi
}

# Gera preview do diff (staged) de 1 arquivo, limitado a N linhas
# Args: $1 = file, $2 = max_lines (default 20)
# Echo: preview + indicador de truncate (stdout)
# Output: primeira linha = preview content, ultima linha = "TRUNCATED: true|false"
ks_approval_diff_preview() {
  local file="$1"
  local max_lines="${2:-20}"

  local full_diff truncated="false"
  full_diff="$(ks_git diff --cached --unified=2 -- "$file" 2>/dev/null | tail -n +5)"
  local total_lines
  total_lines="$(echo "$full_diff" | wc -l)"

  local preview
  if (( total_lines > max_lines )); then
    preview="$(echo "$full_diff" | head -n "$max_lines")"
    truncated="true"
  else
    preview="$full_diff"
  fi

  echo "$preview"
  echo "---TRUNCATED: $truncated---"
}

# Calcula risk level para canonical commit
# Args: $@ = files
# Echo: JSON {level, reason, modifiers}
ks_approval_calc_commit_risk() {
  local files=("$@")
  local n_files=${#files[@]}
  local level="low"
  local modifiers=()
  local reasons=()

  # Contar por classe
  local has_adr_aceita=false has_policy=false has_core=false n_canonical=0
  for f in "${files[@]}"; do
    local class
    class="$(ks_approval_classify_file "$f")"
    case "$class" in
      adr-aceita) has_adr_aceita=true; ((n_canonical++)) ;;
      policy) has_policy=true; ((n_canonical++)) ;;
      core) has_core=true; ((n_canonical++)) ;;
      canonical-other) ((n_canonical++)) ;;
    esac
  done

  # Modificadores
  if $has_adr_aceita; then
    level="medium"
    modifiers+=("adr-aceita")
    reasons+=("mexe em ADR aceita")
  fi
  if $has_policy; then
    level="medium"
    modifiers+=("policy")
    reasons+=("mexe em policy")
  fi
  if $has_core; then
    level="medium"
    modifiers+=("core-architecture")
    reasons+=("mexe em system-map ou knowledge-spine")
  fi
  if (( n_canonical > 3 )); then
    level="medium"
    modifiers+=("many-canonical-files")
    reasons+=("mexe em $n_canonical arquivos canonicos (> 3)")
  fi

  # Diffstat relevante: > 50 linhas somadas
  local diff_total
  diff_total="$(ks_git diff --cached --shortstat 2>/dev/null | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')"
  if (( diff_total > 50 )); then
    if [[ "$level" == "low" ]]; then
      level="medium"
    fi
    modifiers+=("diffstat-relevant:${diff_total}-lines")
    reasons+=("diffstat relevante (${diff_total} linhas)")
  fi

  local reason_txt=""
  if [[ ${#reasons[@]} -gt 0 ]]; then
    reason_txt="$(printf '%s; ' "${reasons[@]}" | sed 's/; $//')"
  else
    reason_txt="Commit local em $n_files arquivo(s) - nao afeta remote ate push"
  fi

  # Rollback template
  local rollback="knowledge-sync restore <pre-canonical-bundle> --apply (preferido, via snapshot pre-canonical) OU git revert HEAD (se ja pushed)"

  jq -nc \
    --arg level "$level" \
    --arg reason "$reason_txt" \
    --arg rollback "$rollback" \
    --argjson mods "$(printf '%s\n' "${modifiers[@]:-base}" | jq -R . | jq -sc .)" \
    '{level: $level, reason: $reason, rollback: $rollback, modifiers_applied: $mods}'
}

# Calcula risk level para canonical push
# Echo: JSON
ks_approval_calc_push_risk() {
  local level="medium"
  local modifiers=("base")
  local reasons=()

  local ahead
  ahead="$(ks_git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"

  if (( ahead > 5 )); then
    level="high"
    modifiers+=("many-commits:${ahead}")
    reasons+=("push de $ahead commits (> 5)")
  fi

  # Verifica se algum commit tem arquivo canonico critico
  local has_critical=false
  if (( ahead > 0 )); then
    local changed_files
    changed_files="$(ks_git diff --name-only '@{u}..HEAD' 2>/dev/null || true)"
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      local class
      class="$(ks_approval_classify_file "$f")"
      if [[ "$class" == "adr-aceita" || "$class" == "policy" || "$class" == "core" ]]; then
        has_critical=true
        break
      fi
    done <<< "$changed_files"
  fi

  if $has_critical; then
    level="high"
    modifiers+=("critical-files")
    reasons+=("inclui mudancas em arquivos criticos (ADR aceita/policy/core)")
  fi

  local reason_txt=""
  if [[ ${#reasons[@]} -gt 0 ]]; then
    reason_txt="$(printf '%s; ' "${reasons[@]}" | sed 's/; $//')"
  else
    reason_txt="Push de $ahead commits rotina"
  fi

  local rollback="git revert <sha> && knowledge-sync canonical push (novo commit corretivo - sem force push)"

  jq -nc \
    --arg level "$level" \
    --arg reason "$reason_txt" \
    --arg rollback "$rollback" \
    --argjson mods "$(printf '%s\n' "${modifiers[@]}" | jq -R . | jq -sc .)" \
    '{level: $level, reason: $reason, rollback: $rollback, modifiers_applied: $mods}'
}

# Calcula risk level para canonical create-marker
# Args: $1 = type (release|milestone), $2 = name, $3 = version
ks_approval_calc_marker_risk() {
  local type="$1" name="$2" version="${3:-}"
  local level="medium"
  local modifiers=("base")
  local reasons=()

  if [[ "$type" == "milestone" ]] && [[ "$name" =~ (internal|test|minor|dev) ]]; then
    level="low"
    modifiers=("milestone-simple")
    reasons+=("milestone interna simples")
  fi

  if [[ "$type" == "release" ]] && [[ "$version" =~ ^v[1-9][0-9]*\. ]]; then
    level="high"
    modifiers+=("major-release")
    reasons+=("release tag major (${version})")
  fi

  local reason_txt=""
  if [[ ${#reasons[@]} -gt 0 ]]; then
    reason_txt="$(printf '%s; ' "${reasons[@]}" | sed 's/; $//')"
  else
    reason_txt="Marker ${type} sobre HEAD atual"
  fi

  local rollback="git tag -d <tag> && git push origin --delete <tag>"

  jq -nc \
    --arg level "$level" \
    --arg reason "$reason_txt" \
    --arg rollback "$rollback" \
    --argjson mods "$(printf '%s\n' "${modifiers[@]}" | jq -R . | jq -sc .)" \
    '{level: $level, reason: $reason, rollback: $rollback, modifiers_applied: $mods}'
}

# Gera card completo para canonical commit
# Args: $1 = commit_message, $2 = why_override (opcional, vazio = auto), $3... = files
ks_approval_build_commit_card() {
  local commit_msg="$1"; shift
  local why_override="$1"; shift
  local files=("$@")
  local n_files=${#files[@]}

  # Scope
  local scope_txt=""
  local has_canonical=0 has_inbox=0
  for f in "${files[@]}"; do
    case "$f" in
      00_inbox/*) ((has_inbox++)) ;;
      *) ((has_canonical++)) ;;
    esac
  done
  if (( has_canonical > 0 && has_inbox == 0 )); then
    scope_txt="$has_canonical arquivo(s) canonico(s)"
  elif (( has_canonical == 0 && has_inbox > 0 )); then
    scope_txt="$has_inbox arquivo(s) em inbox"
  else
    scope_txt="$has_canonical canonico(s) + $has_inbox inbox"
  fi

  # why_now
  local why_now
  if [[ -n "$why_override" ]]; then
    why_now="$why_override"
  else
    local branch
    branch="$(ks_git_branch)"
    why_now="Voce editou $n_files arquivo(s) canonico(s) em ${branch} e solicitou commit agora."
  fi

  # Target
  local branch
  branch="$(ks_git_branch)"
  local files_json
  files_json="$(printf '%s\n' "${files[@]}" | jq -R . | jq -sc .)"
  local target_json
  target_json="$(jq -nc \
    --arg branch "$branch" \
    --arg scope "$scope_txt" \
    --argjson files "$files_json" \
    '{branch: $branch, scope: $scope, files: $files}')"

  # Evidence
  local diffstat
  diffstat="$(ks_approval_diffstat "${files[@]}")"
  local relevant_file
  relevant_file="$(ks_approval_pick_most_relevant_file "${files[@]}")"
  local preview_raw
  preview_raw="$(ks_approval_diff_preview "$relevant_file" 20)"
  local preview_content preview_truncated
  preview_content="$(echo "$preview_raw" | sed '$d')"
  preview_truncated="$(echo "$preview_raw" | tail -1 | sed 's/.*TRUNCATED: \(.*\)---.*/\1/')"

  local evidence_json
  evidence_json="$(jq -nc \
    --arg msg "$commit_msg" \
    --arg diffstat "$diffstat" \
    --arg preview "$preview_content" \
    --arg preview_file "$relevant_file" \
    --argjson truncated "$preview_truncated" \
    '{commit_message: $msg, diffstat: $diffstat, diff_preview: $preview, diff_preview_file: $preview_file, diff_preview_truncated: $truncated}')"

  # Risk
  local risk_json
  risk_json="$(ks_approval_calc_commit_risk "${files[@]}")"

  # Summary
  local summary
  summary="Commit em ${branch}: $(echo "$commit_msg" | head -1)"

  jq -nc \
    --arg summary "$summary" \
    --arg why_now "$why_now" \
    --argjson target "$target_json" \
    --argjson evidence "$evidence_json" \
    --argjson risk "$risk_json" \
    '{summary: $summary, why_now: $why_now, target: $target, evidence: $evidence, risk: $risk}'
}

# Gera card para canonical push
# Args: $1 = why_override
ks_approval_build_push_card() {
  local why_override="${1:-}"

  local branch ahead
  branch="$(ks_git_branch)"
  ahead="$(ks_git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"

  # why_now
  local why_now
  if [[ -n "$why_override" ]]; then
    why_now="$why_override"
  else
    why_now="A branch ${branch} esta ${ahead} commit(s) a frente de origin/${branch} e precisa sincronizar o remoto."
  fi

  # Target
  local target_json
  target_json="$(jq -nc \
    --arg branch "$branch" \
    --arg remote "origin" \
    --argjson ahead "$ahead" \
    '{branch: $branch, remote: $remote, commits_ahead: $ahead}')"

  # Evidence: lista de commits que vao subir
  local commits_list
  commits_list="$(ks_git log --format='%h %s' '@{u}..HEAD' 2>/dev/null | head -10)"
  local is_ff="true"
  if ! ks_git merge-base --is-ancestor '@{u}' HEAD 2>/dev/null; then
    is_ff="false"
  fi

  local evidence_json
  evidence_json="$(jq -nc \
    --arg commits "$commits_list" \
    --argjson is_ff "$is_ff" \
    '{commits_preview: $commits, is_fast_forward: $is_ff}')"

  # Risk
  local risk_json
  risk_json="$(ks_approval_calc_push_risk)"

  local summary="Push de ${ahead} commit(s) de ${branch} para origin/${branch}"

  jq -nc \
    --arg summary "$summary" \
    --arg why_now "$why_now" \
    --argjson target "$target_json" \
    --argjson evidence "$evidence_json" \
    --argjson risk "$risk_json" \
    '{summary: $summary, why_now: $why_now, target: $target, evidence: $evidence, risk: $risk}'
}

# Gera card para canonical create-marker
# Args: $1 = type, $2 = name, $3 = version, $4 = message (commit msg do marker), $5 = tag_name, $6 = why_override
ks_approval_build_marker_card() {
  local type="$1" name="$2" version="$3" message="$4" tag_name="$5" why_override="${6:-}"

  local head_sha
  head_sha="$(ks_git_head_sha)"

  # why_now
  local why_now
  if [[ -n "$why_override" ]]; then
    why_now="$why_override"
  else
    why_now="Foi solicitado um ${type} marker sobre o HEAD atual (${head_sha:0:10}) para registrar este marco."
  fi

  # Target
  local target_json
  target_json="$(jq -nc \
    --arg tag "$tag_name" \
    --arg sha "$head_sha" \
    --arg version "$version" \
    --arg type "$type" \
    '{tag: $tag, head_sha: $sha, version: $version, type: $type}')"

  # Evidence: ultimos 5 commits que esta tag esta marcando
  local recent_commits
  recent_commits="$(ks_git log --format='%h %s' -5 2>/dev/null)"

  local evidence_json
  evidence_json="$(jq -nc \
    --arg commits "$recent_commits" \
    --arg message "$message" \
    '{recent_commits: $commits, marker_message: $message}')"

  # Risk
  local risk_json
  risk_json="$(ks_approval_calc_marker_risk "$type" "$name" "$version")"

  local summary="Criar ${type} tag ${tag_name} em ${head_sha:0:10}"

  jq -nc \
    --arg summary "$summary" \
    --arg why_now "$why_now" \
    --argjson target "$target_json" \
    --argjson evidence "$evidence_json" \
    --argjson risk "$risk_json" \
    '{summary: $summary, why_now: $why_now, target: $target, evidence: $evidence, risk: $risk}'
}

# Versao v2 de ks_approval_create que aceita um "card" estruturado
# Args: $1 = action_name, $2 = context_json (legado), $3 = card_json (novo)
# Retorna approval_id via stdout
ks_approval_create_with_card() {
  local action="$1"
  local context_json="${2:-{\}}"
  local card_json="${3:-{\}}"
  local approval_id
  approval_id="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)-${RANDOM}"
  local short_id="${approval_id:0:8}"

  ks_event_append "canonical_approval_pending" "$(jq -nc \
    --arg id "$approval_id" \
    --arg short "$short_id" \
    --arg action "$action" \
    --argjson context "$context_json" \
    --argjson card "$card_json" \
    '{approval_id: $id, short_id: $short, action: $action, context: $context, card: $card}')"

  echo "$approval_id"
}

# Registra que o card de um approval foi enviado pelo Telegram, capturando ids
# Args: $1 = approval_id, $2 = message_id, $3 = chat_id
ks_approval_record_card_sent() {
  local approval_id="$1"
  local message_id="$2"
  local chat_id="$3"
  ks_event_append "canonical_approval_card_sent" "$(jq -nc \
    --arg id "$approval_id" \
    --arg mid "$message_id" \
    --arg cid "$chat_id" \
    '{approval_id: $id, message_id: $mid, chat_id: $cid}')"
}

# Recupera os ids de mensagem (Telegram) associados ao approval
# Args: $1 = approval_id
# Echo: JSON {message_id, chat_id} ou vazio se nao houver
ks_approval_get_card_ids() {
  local approval_id="$1"
  [[ ! -f "$KS_EVENTS_FILE" ]] && return 1
  jq -rc --arg id "$approval_id" '
    select(.event=="canonical_approval_card_sent" and .payload.approval_id==$id)
    | {message_id: .payload.message_id, chat_id: .payload.chat_id}
  ' "$KS_EVENTS_FILE" 2>/dev/null | tail -1
}

# Edita o card original com um banner de status (APROVADO/EXECUTADO/REJEITADO)
# Args: $1 = approval_id, $2 = banner (texto curto, ex: "✅ APROVADO - aguardando execucao")
# Faz no-op silencioso se nao houver card_sent registrado (deferred/dedup/quiet hours).
ks_approval_edit_card_status() {
  local approval_id="$1"
  local banner="$2"

  local ids
  ids="$(ks_approval_get_card_ids "$approval_id" 2>/dev/null || true)"
  if [[ -z "$ids" || "$ids" == "null" ]]; then
    return 0
  fi
  local message_id chat_id
  message_id="$(echo "$ids" | jq -r '.message_id // empty')"
  chat_id="$(echo "$ids" | jq -r '.chat_id // empty')"
  [[ -z "$message_id" ]] && return 0

  # Recuperar o card original e re-renderizar com banner
  local pending action card_json original_text new_text
  pending="$(grep -F "\"approval_id\":\"$approval_id\"" "$KS_EVENTS_FILE" 2>/dev/null | grep canonical_approval_pending | tail -1)"
  if [[ -z "$pending" ]]; then
    return 0
  fi
  action="$(echo "$pending" | jq -r '.payload.action')"
  card_json="$(echo "$pending" | jq -c '.payload.card')"
  original_text="$(ks_notify_format_approval_card "$approval_id" "$action" "$card_json")"
  new_text="${banner}

${original_text}"

  if ks_notify_edit_telegram "$message_id" "$chat_id" "$new_text"; then
    ks_event_append "canonical_approval_card_edited" "$(jq -nc \
      --arg id "$approval_id" --arg b "$banner" \
      '{approval_id: $id, banner: $b}')"
  else
    ks_event_append "canonical_approval_card_edit_failed" "$(jq -nc \
      --arg id "$approval_id" --arg b "$banner" \
      '{approval_id: $id, banner: $b}')"
  fi
}
