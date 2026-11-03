// clarification-commands — OpenClaw plugin entry point.
//
// Registra 5 slash commands que invocam `cli.sh` da skill clarification-agent
// via execFile, sem passar pelo LLM. Pattern identico ao knowledge-sync-commands.
//
// Spec: bevox-knowledge/35_specs/2026-04-21-e10-telegram-reply-handler.md
// ADR: bevox-knowledge/30_adr/ADR-009-clarification-loop-unified-local-first.md

import { definePluginEntry } from 'openclaw/plugin-sdk/plugin-entry';
import os from 'node:os';
import path from 'node:path';

import { runCli } from './lib/exec.js';
import {
  handlePending,
  handleShow,
  handleOverride,
  handleReject,
  handleRedraft,
} from './lib/commands.js';

const DEFAULT_CLI_PATH = path.join(
  os.homedir(), '.openclaw', 'clarification-agent', 'cli.sh'
);
const DEFAULT_TIMEOUT_MS = 30000;

export default definePluginEntry({
  id: 'clarification-commands',
  name: 'Clarification Commands',
  description:
    'Telegram /clr_* commands wiring clarification-agent CLI to Bernard chat.',

  register(api, { config } = {}) {
    const cliPath = config?.cliPath || DEFAULT_CLI_PATH;
    const timeoutMs = config?.execTimeoutMs || DEFAULT_TIMEOUT_MS;
    const deps = { runCli, cliPath, timeoutMs };

    api.registerCommand({
      name: 'clr_pending',
      nativeNames: { default: 'clr_pending' },
      description: 'List open clarification escalations.',
      acceptsArgs: false,
      requireAuth: true,
      handler: (ctx) => handlePending(ctx, deps),
    });

    api.registerCommand({
      name: 'clr_show',
      nativeNames: { default: 'clr_show' },
      description: 'Show a clarification. Args: <task-id|clarification-id>.',
      acceptsArgs: true,
      requireAuth: true,
      handler: (ctx) => handleShow(ctx, deps),
    });

    api.registerCommand({
      name: 'clr_override',
      nativeNames: { default: 'clr_override' },
      description: 'Override a clarification. Args: <task-id> <texto da resposta>.',
      acceptsArgs: true,
      requireAuth: true,
      handler: (ctx) => handleOverride(ctx, deps),
    });

    api.registerCommand({
      name: 'clr_reject',
      nativeNames: { default: 'clr_reject' },
      description: 'Reject a task via clarification. Args: <task-id> <categoria>: <motivo>.',
      acceptsArgs: true,
      requireAuth: true,
      handler: (ctx) => handleReject(ctx, deps),
    });

    api.registerCommand({
      name: 'clr_redraft',
      nativeNames: { default: 'clr_redraft' },
      description: 'Re-run drafter for a task. Args: <task-id>.',
      acceptsArgs: true,
      requireAuth: true,
      handler: (ctx) => handleRedraft(ctx, deps),
    });
  },
});
