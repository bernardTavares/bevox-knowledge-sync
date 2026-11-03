#!/usr/bin/env bash
# notify.sh - Telegram bridge + dedup + persistence + quiet hours
# Spec section 5

# Configuracao
KS_NOTIFY_CHANNEL="${KS_NOTIFY_CHANNEL:-telegram}"
KS_NOTIFY_TARGET="${KS_NOTIFY_TARGET:-}"  # required: your Telegram chat ID
KS_NOTIFY_DEDUP_WINDOW="${KS_NOTIFY_DEDUP_WINDOW:-3600}"  # 1h
KS_NOTIFY_QUIET_START="${KS_NOTIFY_QUIET_START:-23}"
KS_NOTIFY_QUIET_END="${KS_NOTIFY_QUIET_END:-8}"
KS_NOTIFY_DIRTY_QUIET_WINDOW="${KS_NOTIFY_DIRTY_QUIET_WINDOW:-120}"  # 2min

# Timezone para calculo de quiet hours
# Default: America/Sao_Paulo (Brasilia, UTC-3 sem DST)
# Override: KS_NOTIFY_TIMEZONE=UTC para usar UTC, ou outro nome IANA
KS_NOTIFY_TIMEZONE="${KS_NOTIFY_TIMEZONE:-America/Sao_Paulo}"

# Verifica se estamos em quiet hours (no timezone configurado)
ks_notify_in_quiet_hours() {
  local hour
  hour="$(TZ="$KS_NOTIFY_TIMEZONE" date +%H)"
  hour=$((10#$hour))
  if (( hour >= KS_NOTIFY_QUIET_START || hour < KS_NOTIFY_QUIET_END )); then
    echo "true"
  else
    echo "false"
  fi
}

# Verifica se este evento+severity ja foi notificado dentro do dedup window
# Args: $1 = event_name, $2 = severity, $3 = file_set hash (opcional)
ks_notify_was_recently_sent() {
  local event="$1"
  local severity="$2"
  local file_hash="${3:-}"

  [[ ! -f "$KS_EVENTS_FILE" ]] && { echo "false"; return; }

  local now_ts cutoff_ts
  now_ts="$(date -u +%s)"
  cutoff_ts=$((now_ts - KS_NOTIFY_DEDUP_WINDOW))

  local found
  found="$(jq -rc --arg e "$event" --arg s "$severity" --arg h "$file_hash" --argjson cutoff "$cutoff_ts" '
    select(.event=="notification_sent" and .payload.event_name==$e and .payload.severity==$s and (.payload.file_hash // "")==$h)
    | .ts
    | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime
    | select(. > $cutoff)
  ' "$KS_EVENTS_FILE" 2>/dev/null | tail -1)"

  if [[ -n "$found" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Envia mensagem via OpenClaw para Telegram
# Args: $1 = message text
ks_notify_send_telegram() {
  local message="$1"
  if openclaw message send \
       --channel "$KS_NOTIFY_CHANNEL" \
       --target "$KS_NOTIFY_TARGET" \
       --message "$message" 2>/dev/null; then
    return 0
  fi
  ks_err "failed to send notification via telegram"
  return 1
}

# Envia mensagem com inline buttons via OpenClaw, capturando o messageId
# Args: $1 = message text, $2 = buttons_json (Telegram inline_keyboard array)
# Echo (stdout): JSON {message_id, chat_id} ou vazio em caso de falha
ks_notify_send_telegram_with_buttons() {
  local message="$1"
  local buttons_json="$2"
  local result
  if ! result="$(openclaw message send \
       --channel "$KS_NOTIFY_CHANNEL" \
       --target "$KS_NOTIFY_TARGET" \
       --message "$message" \
       --buttons "$buttons_json" \
       --json 2>/dev/null)"; then
    ks_err "failed to send card with buttons via telegram"
    return 1
  fi
  # Extrair messageId/chatId do payload
  echo "$result" | jq -c '{message_id: (.payload.messageId // .payload.message_id // null), chat_id: (.payload.chatId // .payload.chat_id // null)}'
}

# Edita o texto de uma mensagem ja enviada (mantem buttons existentes)
# Args: $1 = message_id, $2 = chat_id, $3 = novo texto
# Returns 0 em sucesso, 1 em falha
ks_notify_edit_telegram() {
  local message_id="$1"
  local chat_id="$2"
  local new_text="$3"
  local target="${chat_id:-$KS_NOTIFY_TARGET}"
  if openclaw message edit \
       --channel "$KS_NOTIFY_CHANNEL" \
       --target "$target" \
       --message-id "$message_id" \
       --message "$new_text" >/dev/null 2>&1; then
    return 0
  fi
  ks_err "failed to edit telegram message $message_id"
  return 1
}

# Constroi o JSON de inline_keyboard para um approval card
# Args: $1 = short_id (8 chars)
# Echo: JSON array de rows (array of arrays of buttons)
ks_notify_build_approval_buttons() {
  local short_id="$1"
  jq -nc \
    --arg approve "tgcmd:/ks_approve $short_id" \
    --arg reject  "tgcmd:/ks_reject $short_id" \
    --arg pending "tgcmd:/ks_pending" \
    --arg status  "tgcmd:/ks_status $short_id" \
    '[
       [
         {text: "✅ Aprovar",  callback_data: $approve},
         {text: "❌ Rejeitar", callback_data: $reject}
       ],
       [
         {text: "📋 Pendentes", callback_data: $pending},
         {text: "🔎 Status",    callback_data: $status}
       ]
     ]'
}

# Formata mensagem padronizada (5 blocos)
# Args: $1 = event, $2 = severity, $3 = what, $4 = impact, $5 = since, $6 = what_to_do, $7 = commands
ks_notify_format_message() {
  local event="$1" severity="$2" what="$3" impact="$4" since="$5" what_to_do="$6" commands="$7"
  local prefix=""
  [[ "$severity" == "error" ]] && prefix="[CRITICAL] "

  cat <<MSG
${prefix}[knowledge-sync] $event

O QUE ACONTECEU
$what

IMPACTO
$impact

DESDE QUANDO
$since

O QUE FAZER AGORA
$what_to_do

COMANDOS SUGERIDOS
$commands
MSG
}

# Notifica um evento (com toda a logica de policy)
# Args: $1 = event, $2 = severity, $3 = formatted_message_text, $4 = file_hash (opcional)
ks_notify_dispatch() {
  local event="$1" severity="$2" message="$3"
  local file_hash="${4:-}"

  # info -> so events.jsonl, sem mensagem ativa
  if [[ "$severity" == "info" ]]; then
    return 0
  fi

  # Dedup
  if [[ "$(ks_notify_was_recently_sent "$event" "$severity" "$file_hash")" == "true" ]]; then
    ks_log "dedup: skipping $event/$severity"
    return 0
  fi

  # Quiet hours
  if [[ "$(ks_notify_in_quiet_hours)" == "true" ]]; then
    if [[ "$severity" == "error" ]]; then
      # Errors enviam mesmo em quiet hours
      ks_notify_send_telegram "$message"
    else
      # warn fica represado para batch
      ks_event_append "notification_deferred" "$(jq -nc \
        --arg e "$event" --arg s "$severity" --arg m "$message" \
        '{event_name: $e, severity: $s, message: $m, deferred_at: now | strftime("%Y-%m-%dT%H:%M:%SZ")}')"
      return 0
    fi
  else
    ks_notify_send_telegram "$message"
  fi

  ks_event_append "notification_sent" "$(jq -nc \
    --arg e "$event" --arg s "$severity" --arg h "$file_hash" \
    '{event_name: $e, severity: $s, file_hash: $h}')"
}

# =============================================================================
# Approval Card v2 - render dos 6 blocos
# =============================================================================

# Limite de chars para o corpo do card (margem de seguranca - Telegram max 4096)
KS_NOTIFY_CARD_MAX_CHARS="${KS_NOTIFY_CARD_MAX_CHARS:-3500}"

# Renderiza um approval card (6 blocos) para Telegram
# Args: $1 = approval_id, $2 = action, $3 = card_json
# Echo: mensagem formatada
ks_notify_format_approval_card() {
  local approval_id="$1"
  local action="$2"
  local card_json="$3"
  local short_id="${approval_id:0:8}"

  # Extrair campos do card
  local summary why_now
  summary="$(echo "$card_json" | jq -r '.summary // "-"')"
  why_now="$(echo "$card_json" | jq -r '.why_now // "-"')"

  # Target block - varia por action
  local target_block=""
  case "$action" in
    "canonical commit")
      local branch scope
      branch="$(echo "$card_json" | jq -r '.target.branch // "?"')"
      scope="$(echo "$card_json" | jq -r '.target.scope // "-"')"
      target_block="Branch: $branch
Escopo: $scope
Arquivos:"
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        target_block+=$'\n'"  - $f"
      done < <(echo "$card_json" | jq -r '.target.files[]?')
      ;;
    "canonical push")
      local branch remote ahead
      branch="$(echo "$card_json" | jq -r '.target.branch // "?"')"
      remote="$(echo "$card_json" | jq -r '.target.remote // "origin"')"
      ahead="$(echo "$card_json" | jq -r '.target.commits_ahead // 0')"
      target_block="Branch: $branch -> $remote/$branch
Commits a subir: $ahead"
      ;;
    "canonical create-marker")
      local tag head_sha version type
      tag="$(echo "$card_json" | jq -r '.target.tag // "?"')"
      head_sha="$(echo "$card_json" | jq -r '.target.head_sha // "?"')"
      version="$(echo "$card_json" | jq -r '.target.version // "-"')"
      type="$(echo "$card_json" | jq -r '.target.type // "-"')"
      target_block="Tag: $tag
HEAD: ${head_sha:0:10}
Versao: $version
Tipo: $type"
      ;;
  esac

  # Evidence block - varia por action
  local evidence_block=""
  case "$action" in
    "canonical commit")
      local commit_msg diffstat preview preview_file truncated
      commit_msg="$(echo "$card_json" | jq -r '.evidence.commit_message // "-"')"
      diffstat="$(echo "$card_json" | jq -r '.evidence.diffstat // "-"')"
      preview="$(echo "$card_json" | jq -r '.evidence.diff_preview // ""')"
      preview_file="$(echo "$card_json" | jq -r '.evidence.diff_preview_file // ""')"
      truncated="$(echo "$card_json" | jq -r '.evidence.diff_preview_truncated // false')"

      evidence_block="Commit msg: $commit_msg
Diffstat:
$(echo "$diffstat" | sed 's/^/  /')"
      if [[ -n "$preview" && "$preview" != "null" ]]; then
        evidence_block+=$'\n'"Preview (${preview_file}):
$(echo "$preview" | sed 's/^/  /')"
        if [[ "$truncated" == "true" ]]; then
          evidence_block+=$'\n'"  [truncado]"
        fi
      fi
      ;;
    "canonical push")
      local commits is_ff
      commits="$(echo "$card_json" | jq -r '.evidence.commits_preview // "-"')"
      is_ff="$(echo "$card_json" | jq -r '.evidence.is_fast_forward // false')"
      evidence_block="Commits:
$(echo "$commits" | sed 's/^/  /')
Fast-forward: $is_ff"
      ;;
    "canonical create-marker")
      local recent marker_msg
      recent="$(echo "$card_json" | jq -r '.evidence.recent_commits // "-"')"
      marker_msg="$(echo "$card_json" | jq -r '.evidence.marker_message // "-"')"
      evidence_block="Mensagem do marker: $marker_msg
Commits recentes marcados:
$(echo "$recent" | sed 's/^/  /')"
      ;;
  esac

  # Risk block
  local risk_level risk_reason risk_rollback
  risk_level="$(echo "$card_json" | jq -r '.risk.level // "?"' | tr 'a-z' 'A-Z')"
  risk_reason="$(echo "$card_json" | jq -r '.risk.reason // "-"')"
  risk_rollback="$(echo "$card_json" | jq -r '.risk.rollback // "-"')"

  local risk_block="Nivel: $risk_level
Razao: $risk_reason
Rollback: $risk_rollback"

  # Build full message
  local msg
  msg="[knowledge-sync] approval pending [${short_id}]

ACAO
${action}

RESUMO
${summary}

POR QUE AGORA
${why_now}

ALVO
${target_block}

EVIDENCIA
${evidence_block}

RISCO / ROLLBACK
${risk_block}

/approve ${short_id}
/reject ${short_id} --reason \"...\""

  # Truncate if too long
  local msg_len=${#msg}
  if (( msg_len > KS_NOTIFY_CARD_MAX_CHARS )); then
    # Truncate evidence block (most variable) to fit
    local overhead=$((msg_len - KS_NOTIFY_CARD_MAX_CHARS + 200))  # +200 safety
    evidence_block="$(echo "$evidence_block" | head -c $(( ${#evidence_block} - overhead )))
  [truncado - evidencia muito longa para Telegram]"
    msg="[knowledge-sync] approval pending [${short_id}]

ACAO
${action}

RESUMO
${summary}

POR QUE AGORA
${why_now}

ALVO
${target_block}

EVIDENCIA
${evidence_block}

RISCO / ROLLBACK
${risk_block}

/approve ${short_id}
/reject ${short_id} --reason \"...\""
  fi

  echo "$msg"
}
