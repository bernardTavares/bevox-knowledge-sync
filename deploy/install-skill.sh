#!/usr/bin/env bash
# install-skill.sh — copia skill/ source canonico → runtime target.
#
# Source of truth: este repo (skill/).
# Default target: ~/.openclaw/skills/knowledge-sync/
#
# Uso:
#   install-skill.sh                       # cópia padrão (target ~/.openclaw/...)
#   install-skill.sh --target /tmp/ks-X    # target alternativo (testes/smoke)
#   install-skill.sh --dry-run             # lista o que seria copiado, sem agir
#   install-skill.sh --force               # overwrite explicito
#
# Exit codes:
#   0 ok
#   1 erro de argumento ou pré-condição
#   2 source skill/ ausente ou corrupto
#   3 target existe e --force nao foi passado

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SOURCE_DIR="$REPO_DIR/skill"

DEFAULT_TARGET="$HOME/.openclaw/skills/knowledge-sync"
TARGET=""
DRY_RUN=0
FORCE=0

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage ;;
    *) echo "ERROR: argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

TARGET="${TARGET:-$DEFAULT_TARGET}"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source ausente: $SOURCE_DIR" >&2
  exit 2
fi

if [ ! -f "$SOURCE_DIR/SKILL.md" ]; then
  echo "ERROR: source corrupto: $SOURCE_DIR/SKILL.md ausente" >&2
  exit 2
fi

if [ -e "$TARGET" ] && [ "$FORCE" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
  echo "ERROR: target ja existe: $TARGET" >&2
  echo "  use --force pra overwrite ou remova manualmente." >&2
  exit 3
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: copiaria de $SOURCE_DIR/ para $TARGET/"
  echo ""
  echo "Conteudo (source):"
  ( cd "$SOURCE_DIR" && find . -mindepth 1 | sort )
  exit 0
fi

# Cópia atomica via tmpdir + rename
TMP_DIR="$(mktemp -d -t ks-install.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp -aR "$SOURCE_DIR/." "$TMP_DIR/"

# Garante chmod +x explicito nos scripts (git rastreia +x mas
# umask local pode interferir em redeploy)
find "$TMP_DIR/scripts" -type f -name "*.sh" -exec chmod 755 {} +
find "$TMP_DIR/lib" -type f -name "*.sh" -exec chmod 644 {} + 2>/dev/null || true
# Excecao: lib/approval.sh era +x no runtime
[ -f "$TMP_DIR/lib/approval.sh" ] && chmod 755 "$TMP_DIR/lib/approval.sh"

mkdir -p "$(dirname "$TARGET")"
if [ -e "$TARGET" ]; then
  rm -rf "$TARGET"
fi
mv "$TMP_DIR" "$TARGET"
trap - EXIT

echo "OK: instalado em $TARGET"
echo "  files: $(find "$TARGET" -type f | wc -l)"
echo "  symlinks: $(find "$TARGET" -type l | wc -l)"
echo "  executable: $(find "$TARGET" -type f -perm -u+x | wc -l)"
