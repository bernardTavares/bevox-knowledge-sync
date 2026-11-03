# knowledge-sync-commands

> OpenClaw plugin que registra 4 slash commands pra controlar o fluxo
> de approval canônico da skill `knowledge-sync` direto do Telegram,
> sem passar pelo LLM.

**Spec canônica:** `bevox-knowledge/35_specs/2026-04-10-e1.1-fix-plugin-commands.md`

## Comandos

| Comando | Args | O que faz |
|---|---|---|
| `/ks_approve` | `<short_id\|last>` | aprova + executa o canonical commit pendente |
| `/ks_reject` | `<short_id\|last> [reason]` | rejeita o canonical commit pendente |
| `/ks_pending` | — | lista approvals pendentes |
| `/ks_status` | `[short_id]` | mostra status de um approval |

Todos com `requireAuth: true` (default do plugin SDK) — só o sender autorizado executa.

## Como funciona

Plugin usa `api.registerCommand(...)` da plugin SDK do OpenClaw. Esse caminho **bypassa o LLM** (Vox) — o handler JS roda direto no gateway, invoca `bash <skill>/scripts/canonical.sh ...` via `execFile`, captura stdout/stderr e devolve resposta texto pra Telegram.

```
Bernard digita /ks_approve <id>  ou  clica inline button (callback_data="tgcmd:/ks_approve <id>")
        |
        v
gateway resolve via plugin command framework (sem LLM)
        |
        v
handler do plugin (knowledge-sync-commands)
        |
        v
execFile("bash", ["~/.openclaw/skills/knowledge-sync/scripts/canonical.sh", "approve", "<id>"])
        |
        v
execFile("bash", [..., "execute", "<id>"])
        |
        v
retorna { text: "...resultado..." } → Telegram
```

## Install

```bash
openclaw plugins install ~/code/knowledge-sync/plugins/knowledge-sync-commands

# ou via package quando publicado
openclaw plugins install @bevox/knowledge-sync-commands
```

Depois:

```bash
openclaw plugins list                        # confirma "knowledge-sync-commands" presente
openclaw gateway restart                     # se necessário pra reload de commands
```

## Config (opcional)

```json
{
  "plugins": {
    "entries": {
      "knowledge-sync-commands": {
        "config": {
          "scriptsDir": "/path/customizado/scripts",
          "execTimeoutMs": 60000
        }
      }
    }
  }
}
```

Defaults:
- `scriptsDir` = `~/.openclaw/skills/knowledge-sync/scripts/`
- `execTimeoutMs` = `30000` (30s)

## CLI fallback intacto

Plugin **não substitui** o caminho CLI direto. Se o plugin falhar, Bernard continua podendo rodar:

```bash
~/.openclaw/skills/knowledge-sync/scripts/canonical.sh approve <id>
~/.openclaw/skills/knowledge-sync/scripts/canonical.sh execute <id>
```

Trilha auditável (`events.jsonl` da skill) é a mesma nos dois caminhos.

## Limitação conhecida (a validar empiricamente)

Inline buttons do approval card v2 usam `callback_data: "tgcmd:/ks_approve <id>"`. Se a versão atual do OpenClaw rotear o callback como mensagem sintética via DM (em vez de invocar o plugin command handler), comandos textuais funcionam normalmente mas inline buttons continuam quebrados.

Fallback documentado na spec §5 (Approach 3): mudar o `callback_data` builder em `notify.sh` da skill pra `switchInlineQueryCurrentChat`, que cola o comando no input do Telegram. Pendente de decisão explícita do operador.
