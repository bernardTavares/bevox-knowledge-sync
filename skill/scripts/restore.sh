#!/usr/bin/env bash
# restore <bundle> [--target <path>] [--apply]
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/git-ops.sh"
source "$SKILL_DIR/lib/snapshot.sh"

bundle=""
target=""
apply=false
yes=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --apply) apply=true; shift ;;
    --yes) yes=true; shift ;;
    -*) echo "restore: arg desconhecido: $1" >&2; exit 2 ;;
    *) bundle="$1"; shift ;;
  esac
done

if [[ -z "$bundle" ]]; then
  echo "restore: bundle path requerido" >&2
  exit 2
fi

# Resolver path relativo ao snapshots dir se nao for absoluto
if [[ "${bundle:0:1}" != "/" ]]; then
  bundle="$KS_SNAPSHOTS_DIR/$bundle"
fi

if [[ ! -f "$bundle" ]]; then
  echo "restore: bundle nao encontrado: $bundle" >&2
  exit 1
fi

# Default: dry-run
if ! $apply; then
  if [[ -z "$target" ]]; then
    target="/tmp/ks-rollback-$(date +%s)"
  fi
  echo "DRY-RUN: restaurando para $target"
  git clone --quiet "$bundle" "$target"
  echo ""
  echo "OK. Inspecione em: $target"
  echo "Para sobrescrever o clone atual, use: knowledge-sync restore <bundle> --apply"
  ks_event_append "restore_dryrun" "$(jq -nc --arg b "$bundle" --arg t "$target" '{bundle: $b, target: $t}')"
  exit 0
fi

# --apply: hard override (categoria destructive ADR-006 = NEVER em todos levels - exige override)
if ! $yes; then
  echo ""
  echo "  ATENCAO - operacao DESTRUTIVA"
  echo "  Vai sobrescrever $KS_CLONE_PATH com $bundle"
  echo "  Categoria ADR-006: destructive (NEVER em todos os levels - exige override do Bernard)"
  echo ""
  read -r -p "  Digite 'SIM, APLICAR ROLLBACK' para confirmar: " confirm
  if [[ "$confirm" != "SIM, APLICAR ROLLBACK" ]]; then
    echo "  cancelado."
    ks_event_append "restore_apply_cancelled" "$(jq -nc --arg b "$bundle" '{bundle: $b}')"
    exit 1
  fi
fi

# Pre-restore snapshot do estado atual
ks_log "criando pre-restore snapshot do estado atual..."
pre_restore="$(ks_snapshot_create pre-restore "rollback-$(date +%s)")"
ks_log "pre-restore: $pre_restore"

# Restaurar
local_tmp="/tmp/ks-restore-$(date +%s)"
git clone --quiet "$bundle" "$local_tmp"

# Substituir clone atual
backup_old="${KS_CLONE_PATH}.before-restore-$(date +%s)"
mv "$KS_CLONE_PATH" "$backup_old"
mv "$local_tmp" "$KS_CLONE_PATH"

ks_event_append "restore_applied" "$(jq -nc \
  --arg b "$bundle" \
  --arg pre "$pre_restore" \
  --arg backup "$backup_old" \
  '{bundle: $b, pre_restore: $pre, backup_of_old: $backup}')"

echo "OK. Clone atual substituido."
echo "Backup do anterior: $backup_old"
echo "Pre-restore snapshot: $pre_restore"
