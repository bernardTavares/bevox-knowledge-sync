# knowledge-commands plugin

Telegram commands para skill-V2 knowledge watcher (W3.5).

## Comandos

- `/review <gap-id>` — URL da draft branch
- `/dismiss <gap-id>` — mark dismissed (terminal)
- `/postpone <gap-id> <N>` — snooze N dias [1-365]
- `/accept <gap-id> [token]` — 2-step FF-merge release-note → main
- `/retire <gap-id>` — move doc → _retired/ em draft branch
- `/keep <gap-id>` — snooze 90d (F4 retirement only)
- `/keep-permanent <gap-id>` — marker `<!-- knowledge-watcher: do-not-retire -->`

## Config

`~/.openclaw-knowledge/openclaw.json`:
```json
"plugins": {
  "installs": [
    { "id": "knowledge-commands",
      "config": { "operatorAllowlist": ["<bernard_user_id>"] } }
  ]
}
```

## Install

```bash
mkdir -p ~/.openclaw-knowledge/extensions
cp -r ~/code/knowledge-sync/plugins/knowledge-commands ~/.openclaw-knowledge/extensions/
systemctl --user restart openclaw-gateway@knowledge.service
```

## Spec

- `bevox-knowledge/35_specs/_shared/2026-05-08-bevox-knowledge-contribute-skill-v2.md` §11 (W3.5)
- Plan: `bevox-knowledge/35_specs/_shared/plans/2026-05-09-skill-v2-W3.5-telegram-commands-plan.md`
