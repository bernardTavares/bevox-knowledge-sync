#!/usr/bin/env bash
# smoke-bootstrap.sh — prova que install-skill.sh reproduz exatamente
# o runtime atual em ~/.openclaw/skills/knowledge-sync/.
#
# Validacao do bootstrap:
#   1. Estrutura idêntica (diff -rq)
#   2. Conteúdo byte-a-byte (diff -r)
#   3. Mesmo numero de arquivos
#   4. Mesmo conjunto de executaveis
#   5. Sem symlinks externos quebrados
#
# Exit 0 = source equivalente ao runtime.
# Exit 1 = drift detectado.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
RUNTIME="$HOME/.openclaw/skills/knowledge-sync"
TMP_TARGET="$(mktemp -d -t ks-smoke.XXXXXX)"

trap 'rm -rf "$TMP_TARGET"' EXIT

if [ ! -d "$RUNTIME" ]; then
  echo "ERROR: runtime ausente em $RUNTIME — nada para comparar" >&2
  exit 1
fi

echo "==> install em target temporario: $TMP_TARGET"
# install-skill.sh recusa target existente sem --force; tmpdir do
# mktemp ja existe, entao passamos --force.
bash "$SCRIPT_DIR/install-skill.sh" --target "$TMP_TARGET" --force > /dev/null

FAILED=0

echo ""
echo "==> 1. estrutura identica (diff -rq)"
if diff -rq "$TMP_TARGET" "$RUNTIME" > /tmp/ks-smoke-diff.out 2>&1; then
  echo "  OK"
else
  echo "  FAIL — diferencas detectadas:"
  cat /tmp/ks-smoke-diff.out
  FAILED=1
fi

echo ""
echo "==> 2. conteudo byte-a-byte (diff -r, sem flag -q)"
if diff -r "$TMP_TARGET" "$RUNTIME" > /tmp/ks-smoke-content.out 2>&1; then
  echo "  OK"
else
  echo "  FAIL — diferencas de conteudo:"
  head -20 /tmp/ks-smoke-content.out
  FAILED=1
fi

echo ""
echo "==> 3. mesmo numero de arquivos"
n_target=$(find "$TMP_TARGET" -type f | wc -l)
n_runtime=$(find "$RUNTIME" -type f | wc -l)
if [ "$n_target" = "$n_runtime" ]; then
  echo "  OK ($n_target files)"
else
  echo "  FAIL — target=$n_target runtime=$n_runtime"
  FAILED=1
fi

echo ""
echo "==> 4. mesmo conjunto de executaveis (set comparison)"
( cd "$TMP_TARGET" && find . -type f -perm -u+x | sort ) > /tmp/ks-smoke-x-target.out
( cd "$RUNTIME" && find . -type f -perm -u+x | sort ) > /tmp/ks-smoke-x-runtime.out
if diff -q /tmp/ks-smoke-x-target.out /tmp/ks-smoke-x-runtime.out > /dev/null; then
  echo "  OK ($(wc -l < /tmp/ks-smoke-x-target.out) executaveis)"
else
  echo "  FAIL — set de executaveis difere:"
  diff /tmp/ks-smoke-x-target.out /tmp/ks-smoke-x-runtime.out | head -20
  FAILED=1
fi

echo ""
echo "==> 5. symlinks externos quebrados no source"
broken=$(find "$REPO_DIR/skill" -type l -xtype l 2>/dev/null | wc -l)
if [ "$broken" = "0" ]; then
  echo "  OK (nenhum symlink quebrado)"
else
  echo "  FAIL — symlinks quebrados em skill/:"
  find "$REPO_DIR/skill" -type l -xtype l
  FAILED=1
fi

echo ""
if [ "$FAILED" = "0" ]; then
  echo "==> ALL OK — source equivalente ao runtime"
  exit 0
else
  echo "==> FAILED — drift detectado, ver detalhes acima"
  exit 1
fi
