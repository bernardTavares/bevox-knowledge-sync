# knowledge-sync skill

Subsistema operacional do OpenClaw que mantem `bevox-knowledge` como fonte de verdade
ativa sem drift, sem auto-merge, com trilha auditavel.

Implementa o E1 - Knowledge Spine do roadmap OpenClaw Company OS.


## Spec

Canonica: `~/bevox-knowledge/35_specs/2026-04-09-e1-knowledge-spine.md`

## Estado do subsistema

- `state.json` em `~/.openclaw/knowledge-sync/` - fotografia operacional derivada
- `events.jsonl` em `~/.openclaw/knowledge-sync/` - trilha append-only
- snapshots em `~/.openclaw/backups/knowledge-snapshots/`

## Componentes

- **Watcher** (`lib/watcher.sh`) - observa o clone, deriva estado, persiste em state.json. Pure read.
- **Actions** (`scripts/` - tasks futuras) - mutacoes controladas per ADR-006
- **Notifications** (`scripts/` - tasks futuras) - alerta change-of-state via Telegram

## Uso pela Vox

Vox le SKILL.md e executa os scripts conforme instrucoes. Para rodar o Watcher:

```bash
SKILL_DIR=~/.openclaw/skills/knowledge-sync
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/git-ops.sh"
source "$SKILL_DIR/lib/watcher.sh"
ks_watcher_run fetch
```

## CLI standalone

Quando implementado (Task 20): `~/.local/bin/knowledge-sync`

## ADR-006

Esta skill respeita explicitamente a ADR-006 (autonomia, permissions, approvals):

- `canonical commit`/`push`/`create-marker` exigem approval mesmo em L4
- `pull-ff` e a UNICA forma de pull
- Operacoes destrutivas (`reset --hard`, `force push`, `merge`, `rebase`) NAO estao no catalogo
