#!/usr/bin/env bash
# common.sh - shared helpers for knowledge-sync
# Source from other scripts via: source "$SKILL_DIR/lib/common.sh"

# Paths canonicos
KS_CLONE_PATH="${KS_CLONE_PATH:-$HOME/bevox-knowledge}"
KS_STATE_DIR="${KS_STATE_DIR:-$HOME/.openclaw/knowledge-sync}"
KS_STATE_FILE="$KS_STATE_DIR/state.json"
KS_STATE_PREVIOUS_FILE="$KS_STATE_DIR/state.previous.json"
KS_EVENTS_FILE="$KS_STATE_DIR/events.jsonl"
KS_LOCK_FILE="$KS_STATE_DIR/.lock"
KS_SNAPSHOTS_DIR="${KS_SNAPSHOTS_DIR:-$HOME/.openclaw/backups/knowledge-snapshots}"
KS_SNAPSHOTS_INDEX="$KS_SNAPSHOTS_DIR/meta/snapshots-index.jsonl"

# Garantir que dirs existem com permissao 700
ks_ensure_dirs() {
  mkdir -p "$KS_STATE_DIR" "$KS_SNAPSHOTS_DIR"/{auto,pre-canonical,manual,meta}
  chmod 700 "$KS_STATE_DIR" "$KS_SNAPSHOTS_DIR" 2>/dev/null || true
}

# Logging para stderr (nao polui stdout/JSON output)
ks_log() {
  echo "[knowledge-sync] $*" >&2
}

ks_err() {
  echo "[knowledge-sync ERROR] $*" >&2
}

# Lock para impedir execucao concorrente
ks_lock() {
  local timeout="${1:-30}"
  exec 9>"$KS_LOCK_FILE"
  if ! flock -w "$timeout" 9; then
    ks_err "Could not acquire lock within ${timeout}s"
    return 1
  fi
}

ks_unlock() {
  exec 9>&-
}

# Timestamp ISO 8601 UTC
ks_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Verificar dependencias
ks_check_deps() {
  local missing=()
  for cmd in git jq sha256sum flock; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    ks_err "Missing dependencies: ${missing[*]}"
    return 1
  fi
}

# Verificar que o clone existe e e um repo git
ks_check_clone() {
  if [[ ! -d "$KS_CLONE_PATH/.git" ]]; then
    ks_err "Clone not found at $KS_CLONE_PATH"
    return 1
  fi
}

ks_ensure_dirs
