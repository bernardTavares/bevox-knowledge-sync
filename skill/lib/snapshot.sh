#!/usr/bin/env bash
# snapshot.sh - bundle creation, indexing, verification

# Cria um snapshot
# Args: $1 = type (auto-hourly|pre-canonical|manual), $2 = optional slug/context
# Retorna o path do bundle criado via stdout
ks_snapshot_create() {
  local type="$1"
  local slug="${2:-}"

  local now ts_compact
  now="$(ks_now)"
  ts_compact="$(date -u -d "$now" +%Y-%m-%d-%H-%M)"

  local subdir filename
  case "$type" in
    auto-hourly)
      subdir="$KS_SNAPSHOTS_DIR/auto"
      filename="${ts_compact}-auto-hourly.bundle"
      ;;
    pre-canonical)
      subdir="$KS_SNAPSHOTS_DIR/pre-canonical"
      filename="${ts_compact}-pre-canonical-${slug}.bundle"
      ;;
    manual)
      subdir="$KS_SNAPSHOTS_DIR/manual"
      filename="${ts_compact}-manual-${slug:-no-slug}.bundle"
      ;;
    pre-restore)
      subdir="$KS_SNAPSHOTS_DIR/manual"
      filename="${ts_compact}-pre-restore-${slug:-auto}.bundle"
      ;;
    *)
      ks_err "snapshot type unknown: $type"
      return 1 ;;
  esac

  mkdir -p "$subdir"
  local path="$subdir/$filename"

  # Dedup para pre-canonical: se ja existe um pre-canonical recente para o mesmo head_sha, reuse
  if [[ "$type" == "pre-canonical" ]]; then
    local head_sha
    head_sha="$(ks_git_head_sha)"
    local existing
    existing="$(grep -l "\"head_sha\":\"$head_sha\"" "$KS_SNAPSHOTS_INDEX" 2>/dev/null || true)"
    if [[ -n "$existing" ]]; then
      local recent
      recent="$(grep "\"head_sha\":\"$head_sha\"" "$KS_SNAPSHOTS_INDEX" | grep '"type":"pre-canonical"' | tail -1 || true)"
      if [[ -n "$recent" ]]; then
        local recent_path
        recent_path="$KS_SNAPSHOTS_DIR/$(echo "$recent" | jq -r '.path')"
        if [[ -f "$recent_path" ]]; then
          ks_log "dedup: reusing existing pre-canonical snapshot for $head_sha"
          echo "$recent_path"
          return 0
        fi
      fi
    fi
  fi

  # Criar bundle
  ks_git bundle create "$path" --all 2>/dev/null
  chmod 600 "$path"

  # SHA256
  local sha256
  sha256="$(sha256sum "$path" | awk '{print $1}')"

  # Tamanho
  local size
  size="$(stat -c%s "$path")"

  # Branches/tags atuais
  local branches_json tags_json
  branches_json="$(ks_git branch --format='%(refname:short)' 2>/dev/null | jq -R . | jq -sc .)"
  tags_json="$(ks_git tag 2>/dev/null | jq -R . | jq -sc .)"

  local rel_path="${path#$KS_SNAPSHOTS_DIR/}"
  local entry
  entry="$(jq -nc \
    --arg ts "$now" \
    --arg type "$type" \
    --arg path "$rel_path" \
    --argjson size "$size" \
    --arg head_sha "$(ks_git_head_sha)" \
    --argjson branches "$branches_json" \
    --argjson tags "$tags_json" \
    --arg sha256 "$sha256" \
    '{
      ts: $ts,
      type: $type,
      path: $path,
      size_bytes: $size,
      head_sha: $head_sha,
      branches: $branches,
      tags: $tags,
      sha256: $sha256,
      verify_status: "pending",
      verified_at: null
    }')"
  echo "$entry" >> "$KS_SNAPSHOTS_INDEX"
  chmod 600 "$KS_SNAPSHOTS_INDEX"

  echo "$path"
}

# Verifica um bundle: integridade git + sha256 + smoke restore
# Retorna 0 ok, 1 fail
ks_snapshot_verify_one() {
  local path="$1"
  local expected_sha="$2"

  if [[ ! -f "$path" ]]; then
    ks_err "missing: $path"
    return 1
  fi

  local actual_sha
  actual_sha="$(sha256sum "$path" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    ks_err "sha256 mismatch: $path"
    return 1
  fi

  if ! git bundle verify "$path" >/dev/null 2>&1; then
    ks_err "git bundle verify failed: $path"
    return 1
  fi

  # Smoke restore: tentar clone para tmp
  local tmp
  tmp="$(mktemp -d)"
  if ! git clone --quiet "$path" "$tmp/restore" >/dev/null 2>&1; then
    rm -rf "$tmp"
    ks_err "smoke clone failed: $path"
    return 1
  fi
  rm -rf "$tmp"

  return 0
}

# Atualiza verify_status no index para o bundle
ks_snapshot_mark_verified() {
  local rel_path="$1"
  local status="$2"  # verified | failed
  local now
  now="$(ks_now)"

  if [[ ! -f "$KS_SNAPSHOTS_INDEX" ]]; then
    return
  fi

  local tmp
  tmp="$(mktemp)"
  jq -c \
    --arg p "$rel_path" \
    --arg s "$status" \
    --arg t "$now" \
    'if .path == $p then (.verify_status = $s | .verified_at = $t) else . end' \
    "$KS_SNAPSHOTS_INDEX" > "$tmp"
  mv "$tmp" "$KS_SNAPSHOTS_INDEX"
  chmod 600 "$KS_SNAPSHOTS_INDEX"
}

# Rotaciona snapshots conforme retencao por tipo
# auto-hourly: 48h
# pre-canonical: 30d
# manual: 90d
ks_snapshot_rotate() {
  local now_ts
  now_ts="$(date -u +%s)"

  # auto: 48h
  find "$KS_SNAPSHOTS_DIR/auto" -type f -name '*.bundle' 2>/dev/null | while IFS= read -r f; do
    local mtime
    mtime="$(stat -c%Y "$f")"
    if (( now_ts - mtime > 48 * 3600 )); then
      rm -f "$f"
    fi
  done

  # pre-canonical: 30d
  find "$KS_SNAPSHOTS_DIR/pre-canonical" -type f -name '*.bundle' 2>/dev/null | while IFS= read -r f; do
    local mtime
    mtime="$(stat -c%Y "$f")"
    if (( now_ts - mtime > 30 * 86400 )); then
      rm -f "$f"
    fi
  done

  # manual: 90d
  find "$KS_SNAPSHOTS_DIR/manual" -type f -name '*.bundle' 2>/dev/null | while IFS= read -r f; do
    local mtime
    mtime="$(stat -c%Y "$f")"
    if (( now_ts - mtime > 90 * 86400 )); then
      rm -f "$f"
    fi
  done
}
