#!/usr/bin/env bash
# events.sh - events.jsonl append-only audit trail

# Append um evento ao events.jsonl
# Uso: ks_event_append "event_name" '{"key": "value"}'
ks_event_append() {
  local event="$1"
  local payload_json="${2:-null}"
  # Normalize empty/null payload to empty object
  if [[ "$payload_json" == "null" || -z "$payload_json" ]]; then
    payload_json='{}'
  fi
  local now
  now="$(ks_now)"
  local line
  line="$(jq -nc \
    --arg ts "$now" \
    --arg event "$event" \
    --argjson payload "$payload_json" \
    '{ts: $ts, event: $event, payload: $payload}')"
  echo "$line" >> "$KS_EVENTS_FILE"
  chmod 600 "$KS_EVENTS_FILE" 2>/dev/null || true
}

# Le ultimos N eventos
ks_events_tail() {
  local n="${1:-20}"
  if [[ -f "$KS_EVENTS_FILE" ]]; then
    tail -n "$n" "$KS_EVENTS_FILE"
  fi
}

# Filtra eventos por nome
ks_events_filter() {
  local event_name="$1"
  local n="${2:-20}"
  if [[ -f "$KS_EVENTS_FILE" ]]; then
    grep -F "\"event\":\"$event_name\"" "$KS_EVENTS_FILE" | tail -n "$n"
  fi
}
