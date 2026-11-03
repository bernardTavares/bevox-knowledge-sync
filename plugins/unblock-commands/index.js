// unblock-commands — OpenClaw plugin entry point.
//
// Registra 1 slash command (/unblock) que invoca kanban-tasks CLI via execFile,
// sem passar pelo LLM. Pattern espelha clarification-commands.
//
// Spec: bevox-knowledge/35_specs/openclaw/2026-04-29-tester-inconclusive-enrichment.md

import { definePluginEntry } from 'openclaw/plugin-sdk/plugin-entry';
import os from 'node:os';
import path from 'node:path';

import { runCli } from './lib/exec.js';
import { handleUnblock } from './lib/commands.js';

const DEFAULT_KANBAN_CLI = path.join(
  os.homedir(), '.openclaw', 'kanban-tasks', 'cli.sh',
);
const DEFAULT_CLARIFICATION_CLI = path.join(
  os.homedir(), '.openclaw', 'clarification-agent', 'cli.sh',
);
const DEFAULT_TESTER_RUNS_DIR = path.join(
  os.homedir(), '.openclaw', 'tester-agent', 'test_runs',
);
const DEFAULT_RECENCY_HOURS = 24;
const DEFAULT_TIMEOUT_MS = 15000;

export default definePluginEntry({
  id: 'unblock-commands',
  name: 'Unblock Commands',
  description:
    'Telegram /unblock command for resolving tester inconclusive tasks.',

  register(api, { config } = {}) {
    const kanbanCliPath = config?.kanbanCliPath || DEFAULT_KANBAN_CLI;
    const clarificationCliPath = config?.clarificationCliPath || DEFAULT_CLARIFICATION_CLI;
    const testerRunsDir = config?.testerRunsDir || DEFAULT_TESTER_RUNS_DIR;
    const recencyHours = config?.recencyHours || DEFAULT_RECENCY_HOURS;
    const timeoutMs = config?.execTimeoutMs || DEFAULT_TIMEOUT_MS;
    const allowlist = Array.isArray(config?.operatorAllowlist)
      ? config.operatorAllowlist : null;
    const envCsv = process.env.OPENCLAW_GATEWAY_OPERATOR_IDS || '';

    api.registerCommand({
      name: 'unblock',
      nativeNames: { default: 'unblock' },
      description: 'Resolve tester-inconclusive task. Args: <task-id> <pass|cancel|retry|answer> [note].',
      acceptsArgs: true,
      requireAuth: true,
      handler: (ctx) => handleUnblock(ctx, {
        runCli, kanbanCliPath, clarificationCliPath, testerRunsDir,
        allowlist, envCsv, recencyHours, timeoutMs,
      }),
    });
  },
});
