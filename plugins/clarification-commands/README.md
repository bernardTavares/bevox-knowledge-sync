# clarification-commands (OpenClaw plugin)

Telegram slash commands para o clarification-agent (E10 Operational Loop
Hardening wave-3). Registra 5 comandos `/clr_*` via SDK OpenClaw e invoca
`~/.openclaw/clarification-agent/cli.sh` via `execFile`, bypassando LLM.

## Comandos

- `/clr_pending` — lista escalations abertas.
- `/clr_show <task-id | clarification-id>` — mostra question + answer.
- `/clr_override <task-id> <texto>` — aplica override + unblock.
- `/clr_reject <task-id> <categoria>: <motivo>` — rejeita a task.
- `/clr_redraft <task-id>` — re-invoca drafter local-first.

## Auth

`requireAuth: true` declarativo. Gateway valida contra
`elevated.allowFrom.telegram` em `openclaw.json`.

## Instalação (deploy local)

Plugin é consumido via `path` no `openclaw.json` (mesmo pattern do
`knowledge-sync-commands`). Fluxo:

1. Comitar fonte em `bernardTavares/bevox-knowledge-sync` (`plugins/clarification-commands/`).
2. Em `~/.openclaw/openclaw.json` adicionar:

    "plugins": {
      "allow": ["knowledge-sync-commands", "clarification-commands", ...],
      "entries": {
        "clarification-commands": { "enabled": true }
      },
      "installs": {
        "clarification-commands": {
          "source": "path",
          "sourcePath": "~/code/knowledge-sync/plugins/clarification-commands",
          "installPath": "~/.openclaw/extensions/clarification-commands",
          "version": "0.1.0",
          "installedAt": "<ISO timestamp>"
        }
      }
    }

3. Copiar (ou symlink) a pasta pro `installPath`.
4. Gateway reload.

## Tests

    node --test tests/

37 unit tests (parse + format + exec + commands). Zero npm install runtime.

## Rollback

- Desabilitar: `openclaw.json` → `plugins.entries.clarification-commands.enabled: false` + gateway reload.
- Desinstalar: remover `plugins.installs.clarification-commands` + `rm -rf ~/.openclaw/extensions/clarification-commands`.
- CLI direto continua funcionando: `vox clarification override T-XXX --answer "..." --commit`.

## Source

Mirror de `~/code/knowledge-sync/plugins/clarification-commands/`. Spec canônica
em `bevox-knowledge/35_specs/2026-04-21-e10-telegram-reply-handler.md`.
