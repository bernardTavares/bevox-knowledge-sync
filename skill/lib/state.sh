#!/usr/bin/env bash
# state.sh - state.json read/write atomic

# Le o state.json atual (vazio se nao existir)
ks_state_read() {
  if [[ -f "$KS_STATE_FILE" ]]; then
    cat "$KS_STATE_FILE"
  else
    echo "{}"
  fi
}

# Le state.previous.json
ks_state_read_previous() {
  if [[ -f "$KS_STATE_PREVIOUS_FILE" ]]; then
    cat "$KS_STATE_PREVIOUS_FILE"
  else
    echo "{}"
  fi
}

# Escreve state.json atomicamente (tempfile + rename)
# Backup do anterior em state.previous.json
# Uso: echo '{...}' | ks_state_write
ks_state_write() {
  local tmp
  tmp="$(mktemp "$KS_STATE_DIR/state.json.XXXXXX")"
  cat > "$tmp"
  chmod 600 "$tmp"
  # Backup do anterior
  if [[ -f "$KS_STATE_FILE" ]]; then
    cp "$KS_STATE_FILE" "$KS_STATE_PREVIOUS_FILE"
    chmod 600 "$KS_STATE_PREVIOUS_FILE"
  fi
  mv "$tmp" "$KS_STATE_FILE"
}

# Helpers de leitura via jq
ks_state_get() {
  local path="$1"
  ks_state_read | jq -r "$path"
}
