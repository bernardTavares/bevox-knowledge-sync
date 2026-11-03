#!/usr/bin/env bash
# canonical - subcomandos: commit, push, create-marker, approve, reject, execute
# TODOS exigem approval mesmo em L4 (per ADR-006)
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/git-ops.sh"
source "$SKILL_DIR/lib/approval.sh"
source "$SKILL_DIR/lib/notify.sh"
source "$SKILL_DIR/lib/snapshot.sh"
source "$SKILL_DIR/lib/watcher.sh"

ks_check_deps
ks_check_clone

sub="${1:-}"; shift || true

# Funcao comum: validar contexto + criar approval (com card v2) + esperar
# Args: $1 = action name, $2 = context json (legado), $3 = card json (v2)
ks_canonical_request_and_run() {
  local action="$1"
  local context_json="$2"
  local card_json="${3:-{\}}"

  ks_lock 30 || exit 1
  trap 'ks_unlock' EXIT

  # Validacao de contexto comum
  ks_watcher_run
  state="$(ks_state_read)"
  branch="$(echo "$state" | jq -r '.branch.current')"
  if [[ "$branch" != "main" ]]; then
    ks_event_append "action_rejected" "$(jq -nc --arg a "$action" --arg b "$branch" '{action: $a, reason: "must be on main branch", branch: $b}')"
    echo "BLOCKED: precisa estar em main (esta em $branch)" >&2
    exit 3
  fi

  # Para commit/push, validar que nao ha operacao git em progresso
  if [[ "$action" != "canonical create-marker" ]]; then
    local merge_in rebase_in cherry_in
    merge_in="$(echo "$state" | jq -r '.git_operations.merge_in_progress')"
    rebase_in="$(echo "$state" | jq -r '.git_operations.rebase_in_progress')"
    cherry_in="$(echo "$state" | jq -r '.git_operations.cherry_pick_in_progress')"
    if [[ "$merge_in" == "true" || "$rebase_in" == "true" || "$cherry_in" == "true" ]]; then
      echo "BLOCKED: git operation in progress" >&2
      exit 3
    fi
  fi

  # Snapshot pre-canonical (com dedup)
  local current_sha
  current_sha="$(ks_git_head_sha)"
  ks_snapshot_create "pre-canonical" "${current_sha:0:10}-${action// /_}" >/dev/null

  # Criar approval request (com card v2)
  approval_id="$(ks_approval_create_with_card "$action" "$context_json" "$card_json")"
  local short_id="${approval_id:0:8}"

  # Renderizar card v2 (6 blocos) + buttons inline
  card_msg="$(ks_notify_format_approval_card "$approval_id" "$action" "$card_json")"
  buttons_json="$(ks_notify_build_approval_buttons "$short_id")"

  # Politica de envio: cards de approval ignoram quiet hours/dedup,
  # porque cada approval e unico e exige acao do Bernard.
  if send_result="$(ks_notify_send_telegram_with_buttons "$card_msg" "$buttons_json")"; then
    msg_id="$(echo "$send_result" | jq -r '.message_id // empty')"
    chat_id_recv="$(echo "$send_result" | jq -r '.chat_id // empty')"
    if [[ -n "$msg_id" ]]; then
      ks_approval_record_card_sent "$approval_id" "$msg_id" "${chat_id_recv:-$KS_NOTIFY_TARGET}"
    fi
    ks_event_append "notification_sent" "$(jq -nc \
      --arg e "canonical_approval_pending" --arg s "warn" --arg h "$approval_id" \
      '{event_name: $e, severity: $s, file_hash: $h}')"
  else
    ks_event_append "notification_failed" "$(jq -nc \
      --arg id "$approval_id" '{approval_id: $id, channel: "telegram"}')"
  fi

  echo "Approval pendente: $approval_id"
  echo "Short ID: $short_id"
  echo "Aguardando aprovacao do Bernard via Telegram (botoes inline)."
  echo ""
  echo "Fallback CLI:"
  echo "  knowledge-sync canonical approve $short_id"
  echo "  knowledge-sync canonical reject  $short_id [reason]"
  echo "  knowledge-sync canonical execute $short_id"
  echo ""
  echo "Status: pending"

  ks_event_append "${action// /_}_initialized" "$(jq -nc --arg id "$approval_id" '{approval_id: $id, status: "pending"}')"

  ks_unlock
  trap - EXIT
  exit 0
}

case "$sub" in
  commit)
    msg=""
    files=()
    why_override=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -m) msg="$2"; shift 2 ;;
        --why) why_override="$2"; shift 2 ;;
        --files)
          shift
          # Aceita tanto multiplos args separados por espaco quanto um
          # unico arg com vírgulas (`--files a,b` ou `--files "a,b"`),
          # inclusive misturando ambos. Path com vírgula no nome nao e
          # suportado — limitacao conhecida desta normalizacao.
          while [[ $# -gt 0 && "$1" != --* ]]; do
            IFS=',' read -ra _parts <<< "$1"
            for _p in "${_parts[@]}"; do
              [[ -n "$_p" ]] && files+=("$_p")
            done
            shift
          done ;;
        *) shift ;;
      esac
    done
    [[ -z "$msg" ]] && { echo "canonical commit -m <msg> --files <list> [--why <texto>]" >&2; exit 2; }
    [[ ${#files[@]} -eq 0 ]] && { echo "--files <list> requerido (escopo explicito)" >&2; exit 2; }

    # Stage dos arquivos para que diff --cached veja (preview + diffstat no card)
    for f in "${files[@]}"; do
      ks_git add -- "$f" 2>/dev/null || true
    done

    context="$(jq -nc \
      --arg msg "$msg" \
      --argjson files "$(printf '%s\n' "${files[@]}" | jq -R . | jq -sc .)" \
      --arg summary "Commit em main com ${#files[@]} arquivo(s)" \
      '{message: $msg, files: $files, summary: $summary}')"

    # Card v2 com 6 blocos
    card="$(ks_approval_build_commit_card "$msg" "$why_override" "${files[@]}")"

    ks_canonical_request_and_run "canonical commit" "$context" "$card"
    ;;

  push)
    why_override=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --why) why_override="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    context="$(jq -nc --arg summary "Push de main para origin" '{summary: $summary}')"

    # Card v2
    card="$(ks_approval_build_push_card "$why_override")"

    ks_canonical_request_and_run "canonical push" "$context" "$card"
    ;;

  create-marker)
    name=""
    type=""
    message=""
    version=""
    why_override=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name) name="$2"; shift 2 ;;
        --type) type="$2"; shift 2 ;;
        --message) message="$2"; shift 2 ;;
        --version) version="$2"; shift 2 ;;
        --why) why_override="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -z "$name" || -z "$type" ]] && {
      echo "canonical create-marker --name <slug> --type release|milestone [--version vX.Y] [--why <texto>]" >&2
      echo "  --version e obrigatorio para --type release (ex: --version v0.3)" >&2
      exit 2
    }

    case "$type" in
      release)
        if [[ -z "$version" ]]; then
          echo "ERRO: --version e obrigatorio para release (ex: --version v0.3)" >&2
          echo "  Versao deve seguir convencao ADR-004 (kebab-case, semver-like)" >&2
          exit 2
        fi
        # Validacao basica do formato
        if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+ ]]; then
          echo "ERRO: --version deve comecar com vX.Y (ex: v0.3)" >&2
          exit 2
        fi
        tag_name="${version}-${name}"
        ;;
      milestone) tag_name="milestone-$(date +%Y-%m-%d)-$name" ;;
      *) echo "type deve ser release ou milestone" >&2; exit 2 ;;
    esac

    context="$(jq -nc \
      --arg t "$type" --arg n "$name" --arg m "$message" --arg tag "$tag_name" \
      --arg summary "Criar tag $tag_name" \
      '{type: $t, name: $n, message: $m, tag: $tag, summary: $summary}')"

    # Card v2
    card="$(ks_approval_build_marker_card "$type" "$name" "$version" "$message" "$tag_name" "$why_override")"

    ks_canonical_request_and_run "canonical create-marker" "$context" "$card"
    ;;

  execute)
    ref="${1:-}"
    [[ -z "$ref" ]] && { echo "canonical execute <ref>" >&2; exit 2; }

    # Se for short_id ou "last", resolver via ks_approval_resolve_reference
    # Mas execute precisa aceitar um approval que ja foi "granted" (nao mais pending)
    # Por isso nao usa resolve_reference padrao - faz resolucao propria contra granted
    if [[ "$ref" == "last" ]] || [[ ${#ref} -lt 36 ]]; then
      # Prefix matching contra approvals granted recentes
      all_granted_full="$(jq -rc 'select(.event=="canonical_approval_granted") | .payload.approval_id' "$KS_EVENTS_FILE" 2>/dev/null | sort -u)"
      if [[ "$ref" == "last" ]]; then
        # Pega o mais recente granted que ainda nao foi executed
        executed_ids="$(jq -rc 'select(.event=="canonical_committed" or .event=="canonical_pushed" or .event=="canonical_marker_created") | .payload.approval_id // empty' "$KS_EVENTS_FILE" 2>/dev/null | sort -u)"
        resolved=""
        while IFS= read -r gid; do
          [[ -z "$gid" ]] && continue
          if ! echo "$executed_ids" | grep -qx "$gid"; then
            resolved="$gid"
          fi
        done <<< "$all_granted_full"
      else
        matches="$(echo "$all_granted_full" | grep "^${ref}" || true)"
        match_count="$(echo "$matches" | grep -c '^' 2>/dev/null || echo 0)"
        [[ -z "$matches" ]] && match_count=0
        if (( match_count == 1 )); then
          resolved="$matches"
        elif (( match_count == 0 )); then
          resolved=""
        else
          echo "BLOCKED: prefix ambiguo: $matches - use mais caracteres" >&2
          exit 3
        fi
      fi

      if [[ -z "$resolved" ]]; then
        echo "BLOCKED: nenhum approval granted correspondente a '$ref'" >&2
        exit 3
      fi
      approval_id="$resolved"
    else
      approval_id="$ref"
    fi

    if ! ks_approval_check "$approval_id"; then
      echo "BLOCKED: approval ${approval_id:0:8} nao concedido, expirado, ou ja usado" >&2
      exit 3
    fi

    # Recuperar a action e context do evento pending
    pending_event="$(grep -F "\"approval_id\":\"$approval_id\"" "$KS_EVENTS_FILE" | grep canonical_approval_pending | tail -1)"
    action="$(echo "$pending_event" | jq -r '.payload.action')"
    context="$(echo "$pending_event" | jq -c '.payload.context')"

    case "$action" in
      "canonical commit")
        msg="$(echo "$context" | jq -r '.message')"
        files_arr=$(echo "$context" | jq -r '.files[]')
        ks_lock 30 || exit 1
        trap 'ks_unlock' EXIT
        for f in $files_arr; do
          # Arquivo deletado: pathspec nao casa nada no working tree e
          # `git add` (mesmo com -A) falha com "fatal: pathspec did not match".
          # Detecta delete (relativo ao KS_CLONE_PATH, NAO ao CWD do shell)
          # e usa `git rm --cached` pra stage o remove.
          if [ -e "$KS_CLONE_PATH/$f" ]; then
            ks_git add -A -- "$f"
          else
            ks_git rm -f --cached --quiet -- "$f" 2>/dev/null || true
          fi
        done
        if ks_git commit -m "$msg" --quiet; then
          new_sha="$(ks_git_head_sha)"
          ks_event_append "canonical_committed" "$(jq -nc --arg id "$approval_id" --arg s "$new_sha" '{approval_id: $id, sha: $s}')"
          ks_approval_edit_card_status "$approval_id" "✅ EXECUTADO - commit ${new_sha:0:10}" || true
          echo "OK: canonical commit $new_sha"
        else
          ks_event_append "action_failed" "$(jq -nc --arg id "$approval_id" '{approval_id: $id, action: "canonical commit"}')"
          echo "FAILED" >&2
          exit 1
        fi
        ;;

      "canonical push")
        ks_lock 30 || exit 1
        trap 'ks_unlock' EXIT
        if ks_git push origin main; then
          ks_event_append "canonical_pushed" "$(jq -nc --arg id "$approval_id" '{approval_id: $id}')"
          ks_approval_edit_card_status "$approval_id" "✅ EXECUTADO - push origin/main" || true
          echo "OK: canonical push"
        else
          ks_event_append "action_failed" "$(jq -nc --arg id "$approval_id" '{approval_id: $id, action: "canonical push"}')"
          echo "FAILED" >&2
          exit 1
        fi
        ;;

      "canonical create-marker")
        tag="$(echo "$context" | jq -r '.tag')"
        message="$(echo "$context" | jq -r '.message // .summary')"
        ks_lock 30 || exit 1
        trap 'ks_unlock' EXIT
        if ks_git tag -a "$tag" -m "$message" && ks_git push origin "$tag"; then
          ks_event_append "canonical_marker_created" "$(jq -nc --arg id "$approval_id" --arg t "$tag" '{approval_id: $id, tag: $t}')"
          ks_approval_edit_card_status "$approval_id" "✅ EXECUTADO - tag $tag criada" || true
          echo "OK: tag $tag criada e pushed"
        else
          ks_event_append "action_failed" "$(jq -nc --arg id "$approval_id" '{approval_id: $id, action: "canonical create-marker"}')"
          echo "FAILED" >&2
          exit 1
        fi
        ;;

      *)
        echo "action desconhecida no approval: $action" >&2
        exit 1 ;;
    esac
    ;;

  approve)
    # Concede approval explicitamente (uso pelo Bernard via CLI ou bot futuro)
    # Aceita: <UUID>, <prefix de 8+ chars>, "last"
    ref="${1:-}"
    [[ -z "$ref" ]] && { echo "canonical approve <ref>" >&2; exit 2; }

    # Resolver referencia para approval_id real
    if ! ks_resolved_id="$(ks_approval_resolve_reference "$ref" 2>&1)"; then
      # Erro: stderr contem "ERROR <code>"
      ks_err_code="${ks_resolved_id#ERROR }"
      case "$ks_err_code" in
        not_found)
          echo "BLOQUEADO: approval nao encontrado" >&2
          exit 3 ;;
        ambiguous:*)
          ks_err_ids="${ks_err_code#ambiguous:}"
          echo "BLOQUEADO: prefix ambiguo: ${ks_err_ids} - use mais caracteres" >&2
          exit 3 ;;
        expired:*)
          ks_err_id="${ks_err_code#expired:}"
          echo "BLOQUEADO: approval ${ks_err_id:0:8} expirou" >&2
          exit 3 ;;
        executed:*)
          ks_err_id="${ks_err_code#executed:}"
          echo "BLOQUEADO: approval ${ks_err_id:0:8} ja foi executado" >&2
          exit 3 ;;
        rejected:*)
          ks_err_id="${ks_err_code#rejected:}"
          echo "BLOQUEADO: approval ${ks_err_id:0:8} ja foi rejeitado" >&2
          exit 3 ;;
        *)
          echo "BLOQUEADO: erro desconhecido: $ks_err_code" >&2
          exit 3 ;;
      esac
    fi

    # CONTRATO ESTAVEL: imprime o approval_id resolvido na PRIMEIRA LINHA do stdout
    echo "$ks_resolved_id"

    # Concede o approval
    ks_approval_grant "$ks_resolved_id"
    ks_approval_edit_card_status "$ks_resolved_id" "✅ APROVADO - aguardando execucao" || true
    echo "Approval $ks_resolved_id concedido"
    echo "Para executar: knowledge-sync canonical execute $ks_resolved_id"
    ;;

  reject)
    ref="${1:-}"
    reason="${2:-rejected}"
    [[ -z "$ref" ]] && { echo "canonical reject <ref> [reason]" >&2; exit 2; }

    # Resolver referencia
    if ! ks_resolved_id="$(ks_approval_resolve_reference "$ref" 2>&1)"; then
      ks_err_code="${ks_resolved_id#ERROR }"
      case "$ks_err_code" in
        not_found)
          echo "BLOQUEADO: approval nao encontrado" >&2
          exit 3 ;;
        ambiguous:*)
          ks_err_ids="${ks_err_code#ambiguous:}"
          echo "BLOQUEADO: prefix ambiguo: ${ks_err_ids} - use mais caracteres" >&2
          exit 3 ;;
        expired:*)
          ks_err_id="${ks_err_code#expired:}"
          echo "BLOQUEADO: approval ${ks_err_id:0:8} expirou" >&2
          exit 3 ;;
        executed:*)
          ks_err_id="${ks_err_code#executed:}"
          echo "BLOQUEADO: approval ${ks_err_id:0:8} ja foi executado" >&2
          exit 3 ;;
        rejected:*)
          ks_err_id="${ks_err_code#rejected:}"
          echo "BLOQUEADO: approval ${ks_err_id:0:8} ja foi rejeitado" >&2
          exit 3 ;;
        *)
          echo "BLOQUEADO: erro desconhecido: $ks_err_code" >&2
          exit 3 ;;
      esac
    fi

    # CONTRATO: imprime approval_id na primeira linha do stdout
    echo "$ks_resolved_id"

    ks_approval_reject "$ks_resolved_id" "$reason"
    ks_approval_edit_card_status "$ks_resolved_id" "❌ REJEITADO - ${reason}" || true
    echo "Approval $ks_resolved_id rejeitado"
    ;;

  *)
    echo "canonical: subcomando desconhecido: ${sub:-<vazio>}" >&2
    echo "Use: canonical.sh commit -m <msg> --files <list>" >&2
    echo "     canonical.sh push" >&2
    echo "     canonical.sh create-marker --name <slug> --type release|milestone" >&2
    echo "     canonical.sh approve <approval_id>" >&2
    echo "     canonical.sh reject <approval_id> [reason]" >&2
    echo "     canonical.sh execute <approval_id>" >&2
    exit 2 ;;
esac
