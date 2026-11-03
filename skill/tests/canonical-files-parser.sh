#!/usr/bin/env bash
# Test: canonical.sh --files comma syntax parser (E1.1 follow-up)
#
# Verifica que o parser do `--files` em canonical.sh produz um array
# files[] correto para variantes de input (espaco, virgula sem aspas,
# virgula entre aspas, mistura). Bug original: `--files "a,b"` virava
# um unico elemento "a,b" em vez de ["a","b"].
#
# Estrategia E2E real:
#   - tmpdir isolado com clone git fake (init + 1 commit seed)
#   - mock `openclaw` no PATH (notify nao bate em servico real)
#   - roda canonical.sh commit em background, mata logo apos a fase
#     de criacao do approval pending (nao precisa do approve/execute)
#   - le events.jsonl, extrai canonical_approval_pending mais recente
#     e compara context.files com array esperado
#
# Independente: nao toca em ~/.openclaw real, nao toca em
# bevox-knowledge real, nao chama Telegram real.

set -euo pipefail

SKILL_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_SRC/scripts/canonical.sh"

[[ -x "$SCRIPT" ]] || { echo "FAIL: canonical.sh nao encontrado em $SCRIPT" >&2; exit 1; }

TMP="$(mktemp -d -t ks-parser-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# === Setup isolado ===
export KS_CLONE_PATH="$TMP/clone"
export KS_STATE_DIR="$TMP/state"
export KS_SNAPSHOTS_DIR="$TMP/snapshots"
export KS_NOTIFY_TARGET="0"          # nao usado, mas evita default
export KS_NOTIFY_CHANNEL="telegram"
export KS_FETCH_MIN_INTERVAL="999999" # nunca fetch durante teste

mkdir -p "$KS_CLONE_PATH" "$KS_STATE_DIR" "$KS_SNAPSHOTS_DIR/meta" \
         "$KS_SNAPSHOTS_DIR/pre-canonical"

# Init clone fake em main
git -C "$KS_CLONE_PATH" init -q -b main
git -C "$KS_CLONE_PATH" config user.email "test@ks.local"
git -C "$KS_CLONE_PATH" config user.name "ks-test"
echo "seed" > "$KS_CLONE_PATH/seed.md"
git -C "$KS_CLONE_PATH" add seed.md
git -C "$KS_CLONE_PATH" commit -q -m "init"

# Arquivos de teste no clone
for f in fileA.md fileB.md fileC.md; do
  echo "content of $f" > "$KS_CLONE_PATH/$f"
done

# Mock openclaw no PATH (notify devolve JSON valido sem HTTP)
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/openclaw" <<'MOCK'
#!/usr/bin/env bash
# Mock minimo: devolve payload simulando envio bem-sucedido
echo '{"payload":{"messageId":"42","chatId":"0"}}'
MOCK
chmod +x "$MOCK_BIN/openclaw"
export PATH="$MOCK_BIN:$PATH"

EVENTS="$KS_STATE_DIR/events.jsonl"

# Helper: roda canonical.sh commit, espera events.jsonl ter um
# canonical_approval_pending novo, devolve seu context.files (JSON array).
count_approval_events() {
  [[ -f "$EVENTS" ]] || { echo 0; return; }
  jq -rc 'select(.event == "canonical_approval_pending")' "$EVENTS" 2>/dev/null \
    | wc -l | tr -d ' '
}

run_case() {
  local label="$1"; shift
  local before_count
  before_count="$(count_approval_events)"

  # canonical.sh nao bloqueia em loop pos-criacao do approval — ele cria
  # o approval, dispara notify e sai. Rodamos sincrono com timeout.
  timeout 15 bash "$SCRIPT" commit -m "test: $label" "$@" >/dev/null 2>&1 || true

  local now_count
  now_count="$(count_approval_events)"
  if (( now_count <= before_count )); then
    echo "FAIL [$label]: nenhum canonical_approval_pending novo apos a chamada" >&2
    return 1
  fi

  # Pega o ultimo canonical_approval_pending (filtro estrito por .event)
  jq -c 'select(.event == "canonical_approval_pending") | .payload.context.files' \
    "$EVENTS" | tail -1
}

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "  PASS [$label] files = $got"
  else
    echo "  FAIL [$label]"
    echo "    got:  $got"
    echo "    want: $want"
    return 1
  fi
}

echo "=== canonical.sh --files parser tests ==="
fails=0

# Caso 1: 1 arquivo (controle, sempre funcionou)
got="$(run_case "single" --files fileA.md)"
assert_eq "single" "$got" '["fileA.md"]' || fails=$((fails+1))

# Caso 2: multiplos com espaco (controle, sempre funcionou)
got="$(run_case "space-sep" --files fileA.md fileB.md fileC.md)"
assert_eq "space-sep" "$got" '["fileA.md","fileB.md","fileC.md"]' || fails=$((fails+1))

# Caso 3: virgula sem aspas (BUG original)
got="$(run_case "comma-no-quote" --files fileA.md,fileB.md)"
assert_eq "comma-no-quote" "$got" '["fileA.md","fileB.md"]' || fails=$((fails+1))

# Caso 4: virgula entre aspas (BUG principal reportado)
got="$(run_case "comma-quoted" --files "fileA.md,fileB.md")"
assert_eq "comma-quoted" "$got" '["fileA.md","fileB.md"]' || fails=$((fails+1))

# Caso 5: misto (virgula + espaco)
got="$(run_case "mixed" --files "fileA.md,fileB.md" fileC.md)"
assert_eq "mixed" "$got" '["fileA.md","fileB.md","fileC.md"]' || fails=$((fails+1))

echo ""
if (( fails == 0 )); then
  echo "OK: 5/5 casos passaram"
  exit 0
else
  echo "FAIL: $fails caso(s) falharam"
  exit 1
fi
