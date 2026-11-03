// commands.js — 5 handlers para os slash commands /clr_*.
//
// Cada handler recebe (ctx, deps):
//   ctx — PluginCommandContext (SDK): { args, senderId, from, to, messageThreadId, ... }
//   deps — { runCli, cliPath, timeoutMs?, loadNotifierState? }
//
// Retorna { text } — PluginCommandResult do SDK.
//
// Translation de nomes:
//   /clr_pending  → cli.sh escalations --json
//   /clr_show     → cli.sh show <arg> --json
//   /clr_override → cli.sh override <task_id> --answer "<texto>" --commit --json --actor telegram:<id>
//   /clr_reject   → cli.sh reject-task <task_id> --reason "<cat>: <motivo>" --commit --json --actor telegram:<id>
//   /clr_redraft  → cli.sh redraft <task_id> --json --actor telegram:<id>
//
// Cross-validation in handleOverride:
//   Reads notifier-state.json (schema v2) to verify that the /clr_override command
//   is issued from the same chat/thread where the clarification was originally sent.
//   Silent skip on mismatch to prevent accidental resolution across bots/chats.

import {
  formatPending,
  formatShow,
  formatOverride,
  formatReject,
  formatRedraft,
} from './format.js';
import { parseRejectArgs } from './parse.js';
import {
  loadNotifierState as defaultLoadNotifierState,
  findPendingByTaskId,
  crossValidate,
} from './state.js';

function actorOf(ctx) {
  const id = ctx.senderId || 'unknown';
  return `telegram:${id}`;
}

/**
 * Extract bare chat_id from the SDK's `ctx.to` / `ctx.from` field.
 * Telegram contexts set `to` = "telegram:<chatId>" or "telegram:<chatId>:topic:<threadId>".
 * We need the raw numeric chat_id (as string) to compare with notifier-state entry.chat_id.
 */
function extractChatId(toField) {
  if (!toField) return null;
  // Remove "telegram:" prefix
  const withoutPrefix = toField.replace(/^telegram:/, '');
  // Strip ":topic:N" suffix if present
  const parts = withoutPrefix.split(':');
  return parts[0] || null;
}

export async function handlePending(ctx, deps) {
  const result = await deps.runCli(['escalations', '--json'], {
    cliPath: deps.cliPath, timeoutMs: deps.timeoutMs,
  });
  return { text: formatPending(result) };
}

export async function handleShow(ctx, deps) {
  const arg = (ctx.args || '').trim();
  if (!arg) {
    return { text: '❌ Uso: /clr_show <task-id|clarification-id>' };
  }
  const result = await deps.runCli(['show', arg, '--json'], {
    cliPath: deps.cliPath, timeoutMs: deps.timeoutMs,
  });
  return { text: formatShow(result) };
}

export async function handleOverride(ctx, deps) {
  const raw = (ctx.args || '').trim();
  const firstSpace = raw.indexOf(' ');
  if (firstSpace < 0) {
    return { text: '❌ Uso: /clr_override <task-id> <texto da resposta>' };
  }
  const taskId = raw.slice(0, firstSpace).trim();
  const answer = raw.slice(firstSpace + 1).trim();
  if (!taskId || !answer) {
    return { text: '❌ Uso: /clr_override <task-id> <texto da resposta>' };
  }

  // Cross-validation: verify the command comes from the same chat/thread
  // where the clarification was originally sent, and that the cid is still pending.
  const loadState = deps.loadNotifierState || defaultLoadNotifierState;
  const state = loadState();
  const entry = findPendingByTaskId(state, taskId);

  if (!entry) {
    // Check if any resolved entry exists for better error message
    const anyEntry = Object.entries(state.notifications || {}).find(
      ([, e]) => e.task_id === taskId
    );
    if (anyEntry) {
      const [cid, e] = anyEntry;
      return {
        text: `Clarification \`${cid}\` já foi resolvida (status: ${e.status}). Use /clr_show ${taskId} para detalhes.`,
      };
    }
    return {
      text: `Nenhuma clarification pendente para \`${taskId}\`.`,
    };
  }

  // Cross-validate chat_id and thread_id
  const inboundChatId = extractChatId(ctx.to);
  const inboundThreadId = ctx.messageThreadId ?? null;
  const validationError = crossValidate(entry, inboundChatId, inboundThreadId);

  if (validationError) {
    // Log structured warning (silent to user — could be copy-paste from wrong chat)
    console.warn(
      JSON.stringify({
        level: 'warn',
        plugin: 'clarification-commands',
        event: 'clarification_override_cross_validation_failed',
        cid: entry.cid,
        task_id: taskId,
        reason: validationError,
        inbound_chat_id: inboundChatId,
        inbound_thread_id: inboundThreadId,
        entry_chat_id: entry.chat_id,
        entry_thread_id: entry.thread_id,
      })
    );
    return {
      text: `Comando emitido em chat/thread diferente da clarification original.\nUse este comando no mesmo tópico onde a clarification \`${entry.cid}\` foi enviada.`,
    };
  }

  const result = await deps.runCli(
    ['override', taskId, '--answer', answer, '--commit', '--json',
     '--actor', actorOf(ctx)],
    { cliPath: deps.cliPath, timeoutMs: deps.timeoutMs }
  );
  return { text: formatOverride(result) };
}

export async function handleReject(ctx, deps) {
  const raw = (ctx.args || '').trim();
  const firstSpace = raw.indexOf(' ');
  if (firstSpace < 0) {
    return { text: '❌ Uso: /clr_reject <task-id> <categoria>: <motivo>' };
  }
  const taskId = raw.slice(0, firstSpace).trim();
  const rest = raw.slice(firstSpace + 1).trim();
  const parsed = parseRejectArgs(rest);
  if (!taskId || !parsed) {
    return { text: '❌ Uso: /clr_reject <task-id> <categoria>: <motivo>' };
  }
  const reason = `${parsed.category}: ${parsed.reason}`;
  const result = await deps.runCli(
    ['reject-task', taskId, '--reason', reason, '--commit', '--json',
     '--actor', actorOf(ctx)],
    { cliPath: deps.cliPath, timeoutMs: deps.timeoutMs }
  );
  return { text: formatReject(result) };
}

export async function handleRedraft(ctx, deps) {
  const taskId = (ctx.args || '').trim();
  if (!taskId) {
    return { text: '❌ Uso: /clr_redraft <task-id>' };
  }
  const result = await deps.runCli(
    ['redraft', taskId, '--json', '--actor', actorOf(ctx)],
    { cliPath: deps.cliPath, timeoutMs: deps.timeoutMs }
  );
  return { text: formatRedraft(result, taskId) };
}
