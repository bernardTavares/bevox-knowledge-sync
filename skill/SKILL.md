---
name: knowledge-sync
description: 'Subsistema operacional que mantem bevox-knowledge como fonte unica de verdade ativa. Use when: Bernard pede status do knowledge, quer saber se ha mudancas pendentes, quer commitar mudancas em bevox-knowledge, criar/aceitar ADRs, criar snapshots, verificar health do repo, perguntar sobre estado de sync com GitHub, ou listar branches draft. NOT for: edicao livre de qualquer arquivo fora de bevox-knowledge, trabalhos de coding fora do bevox-knowledge, gerenciamento de outros repos git, configuracao do OpenClaw ou sistema operacional.'
---

# Knowledge Sync Skill

Operacionaliza `~/bevox-knowledge` como fonte de verdade ativa do Company OS - sem drift silencioso, sem auto-merge, com trilha auditavel completa.

Spec canonica: `~/bevox-knowledge/35_specs/2026-04-09-e1-knowledge-spine.md`

## When to use

Acionar esta skill quando Bernard pedir qualquer um destes:

- "qual o estado do bevox-knowledge?" / "tem algo pendente?" / "sync ok?"
- "tem mudancas locais no knowledge?" / "working tree limpa?"
- "commitar as mudancas" / "fazer push" / "pull do remote"
- "criar branch draft" / "criar ADR" / "aceitar ADR"
- "snapshot do knowledge" / "backup" / "restaurar"
- "health do knowledge" / "status do repo"
- "eventos recentes" / "historico de sync"

## Components

### Watcher (lib/watcher.sh)

Observa o clone em `~/bevox-knowledge`, deriva estado operacional e persiste em `state.json`. **Pure read - nunca muta o clone.**

Ciclo de checks:
1. `git fetch --quiet origin` (se intervalo minimo `KS_FETCH_MIN_INTERVAL` ultrapassado, default 300s)
2. Branch, ahead/behind, working tree via `git status --porcelain`
3. Operacoes git pendentes (MERGE_HEAD, REBASE_HEAD, CHERRY_PICK_HEAD)
4. Branches `draft/*`
5. Deteccao conservadora de conflito potencial (behind + dirty = risco)
6. Calcula `health.overall`: ok / degraded / critical
7. Escreve `state.json` atomicamente + backup em `state.previous.json`
8. Append em `events.jsonl` para mudancas relevantes

Para rodar o Watcher manualmente:
```bash
SKILL_DIR=~/.openclaw/skills/knowledge-sync
source "$SKILL_DIR/lib/common.sh"
source "$SKILL_DIR/lib/state.sh"
source "$SKILL_DIR/lib/events.sh"
source "$SKILL_DIR/lib/git-ops.sh"
source "$SKILL_DIR/lib/watcher.sh"
ks_watcher_run
```

Para rodar com fetch forcado:
```bash
ks_watcher_run fetch
```

### Actions (scripts/ - implementados em tasks futuras)

Mutacoes controladas no clone. Cada acao e atomica, respeita ADR-006.

Principios hard:
- `pull-ff` e a UNICA forma de pull (nunca `git pull` direto)
- Nenhum `git merge` automatico em conteudo canonico
- `canonical commit`, `canonical push`, `canonical create-marker` exigem **approval explicito** mesmo em L4
- `draft commit`, `draft push` sao **auto** em L4 (per ADR-006 matriz)
- Operacoes destrutivas (`reset --hard`, `force push`, `merge`, `rebase`, `cherry-pick`) **NAO** estao no catalogo

### Notifications (scripts/ - implementados em tasks futuras)

Detecta mudanca relevante de estado comparando `state.json` vs `state.previous.json`. Aplica politica de severidade/persistencia/dedup. Dispara via Telegram (canal principal ate Mission Control existir).

## Commands

### Ler estado atual (sem efeito colateral)
```bash
# Estado operacional completo (JSON)
cat ~/.openclaw/knowledge-sync/state.json | jq .

# Health summary
cat ~/.openclaw/knowledge-sync/state.json | jq .health

# Branch + sync info
cat ~/.openclaw/knowledge-sync/state.json | jq '{branch: .branch, working_tree: .working_tree, health: .health}'
```

### Rodar Watcher (atualiza state.json)
```bash
SKILL_DIR=~/.openclaw/skills/knowledge-sync
bash -c "
  source '$SKILL_DIR/lib/common.sh'
  source '$SKILL_DIR/lib/state.sh'
  source '$SKILL_DIR/lib/events.sh'
  source '$SKILL_DIR/lib/git-ops.sh'
  source '$SKILL_DIR/lib/watcher.sh'
  ks_watcher_run fetch
  ks_state_read | jq .
"
```

### Ver eventos recentes
```bash
tail -20 ~/.openclaw/knowledge-sync/events.jsonl | jq .
```

### Ver snapshots disponiveis
```bash
ls -lah ~/.openclaw/backups/knowledge-snapshots/{auto,pre-canonical,manual}/ 2>/dev/null
cat ~/.openclaw/backups/knowledge-snapshots/meta/snapshots-index.jsonl 2>/dev/null | tail -10 | jq .
```

### Git direto no clone (operacoes read-only seguras)
```bash
git -C ~/bevox-knowledge status
git -C ~/bevox-knowledge log --oneline -10
git -C ~/bevox-knowledge diff
git -C ~/bevox-knowledge branch -a
```

## Approval flow

**Regra fundamental (ADR-006):** Autonomia do Vox depende da categoria da operacao:

| Categoria | Exemplos | Autonomia L4 |
|---|---|---|
| `read-internal` | status, events, diff, log | auto |
| `read-external` | fetch | auto |
| `write-internal` | pull-ff, snapshot create | auto |
| `write-knowledge-draft` | draft commit, draft push | auto + push branch |
| `write-knowledge-canonical` | canonical commit, canonical push, create-marker | **approve** |
| `destructive` | restore --apply, reset --hard | **NEVER** sem override explicito |

**Para acoes canonicas:** SEMPRE pedir aprovacao ao Bernard antes de executar. Apresentar o diff ou resumo das mudancas e aguardar confirmacao explicita. Nao executar `canonical commit` ou `canonical push` automaticamente, mesmo que Bernard nao tenha dito "aprove" explicitamente - pedir confirmacao.

Exemplo de prompt para approval:
```
Pronto para commitar em main:
- 3 arquivos modificados: 30_adr/ADR-007-foo.md, system-map.md, ...
- Mensagem: "feat(adr): accept ADR-007 - foo bar"

Confirma? (sim/nao)
```

## Files and state

| Arquivo | Descricao |
|---|---|
| `~/.openclaw/knowledge-sync/state.json` | Fotografia operacional derivada. Valida ate o proximo ciclo do Watcher. NAO e a verdade - verdade e o clone git + remote |
| `~/.openclaw/knowledge-sync/state.previous.json` | Estado anterior para diff comparison |
| `~/.openclaw/knowledge-sync/events.jsonl` | Trilha append-only de eventos. Nunca apagado |
| `~/.openclaw/backups/knowledge-snapshots/auto/` | Bundles automaticos (cron) |
| `~/.openclaw/backups/knowledge-snapshots/pre-canonical/` | Bundles antes de commit canonical |
| `~/.openclaw/backups/knowledge-snapshots/manual/` | Bundles criados sob demanda |
| `~/.openclaw/backups/knowledge-snapshots/meta/snapshots-index.jsonl` | Indice de todos os snapshots |

## Lib files (internos, use via source)

| Arquivo | Funcao |
|---|---|
| `lib/common.sh` | Variaveis de path, helpers de log, lock, timestamp, check deps |
| `lib/state.sh` | Leitura/escrita atomica do state.json |
| `lib/events.sh` | Append em events.jsonl, leitura de eventos |
| `lib/git-ops.sh` | Wrappers git seguros para o clone |
| `lib/watcher.sh` | Ciclo completo do Watcher (ks_watcher_run) |

## Health issue codes

| Code | Severidade | Significado |
|---|---|---|
| `working_tree_dirty` | warn | Working tree tem arquivos modificados/untracked/staged |
| `branch_behind` | warn | Branch local atras do tracking |
| `branch_ahead` | info (warn apos 24h) | Branch local a frente do tracking (commits nao publicados) |
| `merge_in_progress` | warn | Operacao git de merge em curso |
| `rebase_in_progress` | warn | Operacao git de rebase em curso |
| `cherry_pick_in_progress` | warn | Operacao git de cherry-pick em curso |
| `conflict_potential` | error | Risco de conflito impedindo FF seguro |
| `draft_branch_stale` | info (warn apos 7d) | Branch draft sem atividade ha muito tempo |
| `watcher_stale` | error | Watcher nao roda ha mais que 15 min |
| `fetch_failed` | error | Ultimo fetch falhou |
| `detached_head` | warn | HEAD detached |

## When NOT to use

- Edicao de arquivos em qualquer repo que NAO seja bevox-knowledge
- Trabalhos de coding (features, bugs, refactoring) - use o fluxo normal de desenvolvimento
- Configuracao do OpenClaw, sistema operacional, ou infra
- Gerenciamento de outros repos git do Bernard
- Analise de logs de sistema ou monitoring geral
- Qualquer operacao que nao envolva o estado ou conteudo de bevox-knowledge

## Telegram Approval Mode

Os comandos `/ks_approve`, `/ks_reject`, `/ks_pending` e `/ks_status` NAO sao
mais responsabilidade desta skill via Vox. Eles sao tratados nativamente pelo
plugin OpenClaw `knowledge-sync-commands`, que registra os 4 comandos via
`api.registerCommand(...)` da plugin SDK e invoca `canonical.sh`/`pending.sh`/
`status.sh` desta skill via `execFile`, **bypassando o LLM**.

Source canonico do plugin: `bernardTavares/bevox-knowledge-sync` (mono-repo,
sub-pasta `plugins/knowledge-sync-commands/`).

Fluxo operacional:

```
Bernard digita /ks_approve <id>  ou  clica inline button no card v2
        |
        v
gateway resolve via plugin command framework (NAO passa pelo LLM)
        |
        v
plugin handler -> bash <skill>/scripts/canonical.sh approve|execute|reject|...
        |
        v
trilha auditavel preservada em events.jsonl da skill
```

CLI fallback continua disponivel como contingencia (`canonical.sh approve <id>`
direto no terminal).

Spec do fix: `bevox-knowledge/35_specs/2026-04-10-e1.1-fix-plugin-commands.md`.
