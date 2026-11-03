import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { handleUnblock } from '../lib/commands.js';

function makeCtx({ args = '', senderId = '111', from = { username: 'bernard' } } = {}) {
  return { args, senderId, from, channel: 'telegram' };
}

function makeTesterRun(dir, taskId, withinHours) {
  const tsMs = Date.now() - withinHours * 3600 * 1000;
  const ts = new Date(tsMs).toISOString();
  const runId = `${taskId}-tr-1`;
  const filePath = path.join(dir, `${runId}.json`);
  writeFileSync(filePath, JSON.stringify({
    test_run_id: runId,
    task_id: taskId,
    decision: 'in_progress_test_inconclusive',
    finished_at: ts,
    checks: [],
  }, null, 2));
  return filePath;
}

function fakeCliFactory(behavior) {
  return async (args) => {
    if (behavior?.fail) {
      return { ok: false, stderr: 'simulated failure', code: 1 };
    }
    return { ok: true, stdout: JSON.stringify({ task_id: args[1], moved: true }), stderr: '' };
  };
}

test('rejects unauthorized sender', async () => {
  const tmp = mkdtempSync(path.join(tmpdir(), 'ub-'));
  const reply = await handleUnblock(makeCtx({ args: 'T-0155 pass', senderId: '999' }), {
    runCli: fakeCliFactory(),
    kanbanCliPath: '/fake/cli.sh',
    testerRunsDir: tmp,
    allowlist: ['111'],
    recencyHours: 24,
  });
  assert.match(reply.text, /não autorizado/);
});

test('rejects bad usage', async () => {
  const tmp = mkdtempSync(path.join(tmpdir(), 'ub-'));
  const reply = await handleUnblock(makeCtx({ args: 'foo bar' }), {
    runCli: fakeCliFactory(),
    kanbanCliPath: '/fake/cli.sh',
    testerRunsDir: tmp,
    allowlist: ['111'],
    recencyHours: 24,
  });
  assert.match(reply.text, /Uso:/);
});

test('rejects pass when no recent test_run within window', async () => {
  const tmp = mkdtempSync(path.join(tmpdir(), 'ub-'));
  makeTesterRun(tmp, 'T-0155', 48);  // 48h old, window is 24h
  const reply = await handleUnblock(makeCtx({ args: 'T-0155 pass' }), {
    runCli: fakeCliFactory(),
    kanbanCliPath: '/fake/cli.sh',
    testerRunsDir: tmp,
    allowlist: ['111'],
    recencyHours: 24,
  });
  assert.match(reply.text, /nenhum test_run inconclusivo/);
});

test('cancel does not require recent test_run', async () => {
  const tmp = mkdtempSync(path.join(tmpdir(), 'ub-'));
  // No test_run at all.
  const calls = [];
  const reply = await handleUnblock(makeCtx({ args: 'T-9999 cancel sem propósito' }), {
    runCli: async (args) => { calls.push(args); return { ok: true, stdout: '{}', stderr: '' }; },
    kanbanCliPath: '/fake/cli.sh',
    testerRunsDir: tmp,
    allowlist: ['111'],
    recencyHours: 24,
  });
  assert.match(reply.text, /cancelada/);
  // Verify CLI invoked: unblock then move rejected
  assert.deepEqual(calls[0].slice(0, 3), ['task', 'unblock', 'T-9999']);
  assert.deepEqual(calls[1].slice(0, 4), ['task', 'move', 'T-9999', 'rejected']);
});

test('pass appends human_unblock to test_run JSON', async () => {
  const tmp = mkdtempSync(path.join(tmpdir(), 'ub-'));
  const trPath = makeTesterRun(tmp, 'T-0155', 1);  // 1h old, fresh
  const reply = await handleUnblock(makeCtx({ args: 'T-0155 pass validei no host' }), {
    runCli: fakeCliFactory(),
    kanbanCliPath: '/fake/cli.sh',
    testerRunsDir: tmp,
    allowlist: ['111'],
    recencyHours: 24,
  });
  assert.match(reply.text, /destravada como pass/);
  const tr = JSON.parse(readFileSync(trPath, 'utf-8'));
  assert.ok(tr.human_unblock, 'human_unblock block missing');
  assert.equal(tr.human_unblock.decision, 'pass');
  assert.equal(tr.human_unblock.note, 'validei no host');
  assert.equal(tr.human_unblock.via, 'telegram-slash-command');
  assert.match(tr.human_unblock.decided_at, /^\d{4}-\d{2}-\d{2}T/);
});

test('cli failure surfaces error reply', async () => {
  const tmp = mkdtempSync(path.join(tmpdir(), 'ub-'));
  makeTesterRun(tmp, 'T-0155', 1);
  const reply = await handleUnblock(makeCtx({ args: 'T-0155 pass' }), {
    runCli: fakeCliFactory({ fail: true }),
    kanbanCliPath: '/fake/cli.sh',
    testerRunsDir: tmp,
    allowlist: ['111'],
    recencyHours: 24,
  });
  assert.match(reply.text, /falha no kanban CLI/);
});
