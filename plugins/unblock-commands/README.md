# unblock-commands

Telegram `/unblock <task-id> pass|cancel [note]` for resolving tester
inconclusive tasks without leaving Telegram.

Spec: `bevox-knowledge/35_specs/openclaw/2026-04-29-tester-inconclusive-enrichment.md`.

## Behaviour

- `/unblock T-XXXX pass [nota]` — moves task to `done` with reason
  `human-unblock-pass: <nota>`; appends `human_unblock` block to the most
  recent test_run JSON for that task.
- `/unblock T-XXXX cancel [motivo]` — moves task to `rejected` with reason
  `human-unblock-cancel: <motivo>`; appends `human_unblock` block.

## Authorization

- Sender must be in `operatorAllowlist` (config) or `OPENCLAW_GATEWAY_OPERATOR_IDS`
  (env, csv).
- Chat must match the dispatcher chat configured for the project (validated by
  the gateway router; this plugin does not re-validate).

## Tests

```bash
npm test
```
