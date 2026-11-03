// knowledge-commands — OpenClaw plugin entry point.
//
// Registra 7 slash commands (/review /dismiss /postpone /accept /retire
// /keep /keep-permanent) que invocam ~/.openclaw/kanban-tasks/cli.sh
// `knowledge <subcmd> <args>`.
//
// Spec: bevox-knowledge/35_specs/_shared/2026-05-08-bevox-knowledge-contribute-skill-v2.md §11 (W3.5)
// Plan: bevox-knowledge/35_specs/_shared/plans/2026-05-09-skill-v2-W3.5-telegram-commands-plan.md

import { definePluginEntry } from 'openclaw/plugin-sdk/plugin-entry';
import os from 'node:os';
import path from 'node:path';

import { runCli } from './lib/exec.js';
import {
  handleReview, handleDismiss, handlePostpone, handleAccept,
  handleRetire, handleKeep, handleKeepPermanent,
} from './lib/commands.js';

const DEFAULT_KANBAN_CLI = path.join(
  os.homedir(), '.openclaw', 'kanban-tasks', 'cli.sh',
);
const DEFAULT_TIMEOUT_MS = 20000;

const COMMANDS = [
  { name: 'review', desc: 'Abre URL da draft branch/main do gap. Args: <gap-id>',
    handler: handleReview },
  { name: 'dismiss', desc: 'Marca gap dismissed (terminal). Args: <gap-id>',
    handler: handleDismiss },
  { name: 'postpone', desc: 'Snooze N dias. Args: <gap-id> <N>',
    handler: handlePostpone },
  { name: 'accept', desc: 'FF-merge release-note → main (2-step). Args: <gap-id> [token]',
    handler: handleAccept },
  { name: 'retire', desc: 'Move doc → _retired/ em draft branch. Args: <gap-id>',
    handler: handleRetire },
  { name: 'keep', desc: 'Snooze 90d (F4 only). Args: <gap-id>',
    handler: handleKeep },
  { name: 'keep-permanent', desc: 'Marker do-not-retire em doc body. Args: <gap-id>',
    handler: handleKeepPermanent },
];

export default definePluginEntry({
  id: 'knowledge-commands',
  name: 'Knowledge Commands',
  description: 'Telegram commands for skill-V2 knowledge watcher (F1 + F4 actions).',

  register(api, { config } = {}) {
    const kanbanCliPath = config?.kanbanCliPath || DEFAULT_KANBAN_CLI;
    const timeoutMs = config?.execTimeoutMs || DEFAULT_TIMEOUT_MS;
    const allowlist = Array.isArray(config?.operatorAllowlist)
      ? config.operatorAllowlist : null;
    const envCsv = process.env.OPENCLAW_GATEWAY_OPERATOR_IDS || '';
    for (const cmd of COMMANDS) {
      api.registerCommand({
        name: cmd.name,
        nativeNames: { default: cmd.name },
        description: cmd.desc,
        acceptsArgs: true,
        requireAuth: true,
        handler: (ctx) => cmd.handler(ctx, {
          runCli, kanbanCliPath, allowlist, envCsv, timeoutMs,
        }),
      });
    }
  },
});
