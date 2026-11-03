// commands.js — /unblock orchestration: parse → auth → tester runs → kanban CLI.

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import path from 'node:path';

import { parseUnblockArgs } from './parse.js';
import { isAuthorized } from './auth.js';
import {
  formatPassSuccess, formatCancelSuccess, formatUnauthorized,
  formatBadUsage, formatStaleTestRun, formatCliError,
  formatRetrySuccess, formatAnswerSuccess,
} from './format.js';

function nowIso() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function findLatestInconclusiveRun(testerRunsDir, taskId, recencyHours) {
  let entries;
  try {
    entries = readdirSync(testerRunsDir);
  } catch {
    return null;
  }
  const prefix = `${taskId}-tr-`;
  const candidates = entries
    .filter((f) => f.startsWith(prefix) && f.endsWith('.json'))
    .map((f) => path.join(testerRunsDir, f));

  let best = null;
  for (const p of candidates) {
    let raw;
    try { raw = readFileSync(p, 'utf-8'); } catch { continue; }
    let data;
    try { data = JSON.parse(raw); } catch { continue; }
    if (data.decision !== 'in_progress_test_inconclusive') continue;
    if (!data.finished_at) continue;
    const finishedMs = Date.parse(data.finished_at);
    if (Number.isNaN(finishedMs)) continue;
    const ageHours = (Date.now() - finishedMs) / (3600 * 1000);
    if (ageHours > recencyHours) continue;
    if (!best || finishedMs > best.finishedMs) {
      best = { path: p, finishedMs, data };
    }
  }
  return best;
}

function appendHumanUnblock(runPath, runData, { decision, note, operatorId, operatorHandle }) {
  runData.human_unblock = {
    decision,
    operator: String(operatorId || 'unknown'),
    operator_handle: operatorHandle || null,
    decided_at: nowIso(),
    note: note || null,
    via: 'telegram-slash-command',
  };
  writeFileSync(runPath, JSON.stringify(runData, null, 2));
}

export async function handleUnblock(ctx, deps) {
  const {
    runCli, kanbanCliPath, clarificationCliPath, testerRunsDir,
    allowlist, envCsv, recencyHours = 24, timeoutMs = 15000,
  } = deps;

  const senderId = ctx.senderId;
  const operatorHandle = ctx.from?.username || null;

  if (!isAuthorized(senderId, { allowlist, envCsv })) {
    return { text: formatUnauthorized() };
  }

  const parsed = parseUnblockArgs(ctx.args || '');
  if (!parsed) {
    return { text: formatBadUsage() };
  }
  const { taskId, subcommand, note } = parsed;

  // Dispatch retry/answer to clarification-agent canonical Python
  if (subcommand === 'retry' || subcommand === 'answer') {
    const ubnArgs = subcommand === 'retry'
      ? ['ubn', 'retry', taskId]
      : ['ubn', 'answer', taskId, '--text', note];
    const r = await runCli(ubnArgs, { cliPath: clarificationCliPath, timeoutMs });
    if (!r.ok) {
      return { text: formatCliError(taskId, r.stderr || r.message) };
    }
    // Parse JSON output from ubn_actions.main()
    let summary = 'completed';
    try {
      const parsed = JSON.parse(r.stdout);
      summary = parsed.summary || summary;
    } catch (_) { /* ignore parse errors, use default summary */ }
    return {
      text: subcommand === 'retry'
        ? formatRetrySuccess(taskId, summary, operatorHandle)
        : formatAnswerSuccess(taskId, operatorHandle),
    };
  }

  let testerRun = null;
  if (subcommand === 'pass') {
    testerRun = findLatestInconclusiveRun(testerRunsDir, taskId, recencyHours);
    if (!testerRun) {
      return { text: formatStaleTestRun(taskId, recencyHours) };
    }
  } else if (subcommand === 'cancel') {
    // cancel doesn't require a recent test_run; still try to annotate if present.
    testerRun = findLatestInconclusiveRun(testerRunsDir, taskId, recencyHours);
  }

  const targetState = subcommand === 'pass' ? 'done' : 'rejected';
  const moveReason = subcommand === 'pass'
    ? `human-unblock-pass${note ? `: ${note.slice(0, 200)}` : ''}`
    : `human-unblock-cancel${note ? `: ${note.slice(0, 200)}` : ''}`;
  const actor = `telegram:${senderId}`;
  const opts = { cliPath: kanbanCliPath, timeoutMs };

  // 1) task unblock <id>
  const r1 = await runCli(['task', 'unblock', taskId, '--actor', actor, '--json'], opts);
  if (!r1.ok) {
    return { text: formatCliError(taskId, r1.stderr || r1.message) };
  }

  // 2) task move <id> <state> --reason <reason>
  const r2 = await runCli(
    ['task', 'move', taskId, targetState, '--actor', actor,
     '--reason', moveReason, '--json'],
    opts,
  );
  if (!r2.ok) {
    return { text: formatCliError(taskId, r2.stderr || r2.message) };
  }

  // 3) Annotate test_run JSON if present.
  if (testerRun) {
    try {
      appendHumanUnblock(testerRun.path, testerRun.data, {
        decision: subcommand, note,
        operatorId: senderId, operatorHandle,
      });
    } catch (e) {
      // Annotation failure is non-fatal; kanban already mutated. Log via stderr.
      console.error(`[unblock-commands] human_unblock write failed: ${e.message}`);
    }
  }

  if (subcommand === 'pass') {
    return { text: formatPassSuccess(taskId, operatorHandle) };
  }
  return { text: formatCancelSuccess(taskId, operatorHandle) };
}
