import { test } from 'node:test';
import assert from 'node:assert';
import {
  handleReview, handleDismiss, handlePostpone, handleAccept,
  handleRetire, handleKeep, handleKeepPermanent,
} from '../lib/commands.js';

const ALLOWED = '12345';

function mockOk(stdout = 'ok') {
  return async () => ({ ok: true, stdout, stderr: '' });
}

function mockFail(stderr = 'err') {
  return async () => ({ ok: false, stdout: '', stderr });
}

test('handleReview happy path', async () => {
  const ctx = { senderId: ALLOWED, args: 'bevox-direct-aaa-spec' };
  const r = await handleReview(ctx, {
    runCli: mockOk('🔗 url'), kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.match(r.text, /🔗 url/);
});

test('handleReview unauthorized', async () => {
  const ctx = { senderId: 'bad', args: 'bevox-direct-aaa-spec' };
  const r = await handleReview(ctx, {
    runCli: mockOk(), kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.match(r.text, /não autorizado/);
});

test('handleReview bad usage', async () => {
  const ctx = { senderId: ALLOWED, args: '' };
  const r = await handleReview(ctx, {
    runCli: mockOk(), kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.match(r.text, /<gap-id>/);
});

test('handlePostpone passes days arg', async () => {
  let captured = null;
  const runCli = async (args) => { captured = args; return { ok: true, stdout: 'done', stderr: '' }; };
  const ctx = { senderId: ALLOWED, args: 'bevox-direct-aaa-spec 7' };
  await handlePostpone(ctx, {
    runCli, kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.deepEqual(captured, ['knowledge', 'postpone', 'bevox-direct-aaa-spec', '7']);
});

test('handleAccept without token', async () => {
  let captured = null;
  const runCli = async (args) => { captured = args; return { ok: true, stdout: 'token-step1', stderr: '' }; };
  const ctx = { senderId: ALLOWED, args: 'bevox-direct-aaa-spec' };
  await handleAccept(ctx, {
    runCli, kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.deepEqual(captured, ['knowledge', 'accept', 'bevox-direct-aaa-spec']);
});

test('handleAccept with token', async () => {
  let captured = null;
  const runCli = async (args) => { captured = args; return { ok: true, stdout: 'merged', stderr: '' }; };
  const ctx = { senderId: ALLOWED, args: 'bevox-direct-aaa-spec abc123' };
  await handleAccept(ctx, {
    runCli, kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.deepEqual(captured, ['knowledge', 'accept', 'bevox-direct-aaa-spec', 'abc123']);
});

test('handleDismiss CLI error returned', async () => {
  const ctx = { senderId: ALLOWED, args: 'bevox-direct-aaa-spec' };
  const r = await handleDismiss(ctx, {
    runCli: mockFail('python error'), kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.match(r.text, /erro CLI/);
});

test('handleRetire happy path', async () => {
  const ctx = { senderId: ALLOWED, args: 'bevox-direct-r-aaa' };
  const r = await handleRetire(ctx, {
    runCli: mockOk('retired'), kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.match(r.text, /retired/);
});

test('handleKeep happy path', async () => {
  const ctx = { senderId: ALLOWED, args: 'bevox-direct-r-aaa' };
  const r = await handleKeep(ctx, {
    runCli: mockOk('kept'), kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.match(r.text, /kept/);
});

test('handleKeepPermanent happy path', async () => {
  const ctx = { senderId: ALLOWED, args: 'bevox-direct-r-aaa' };
  const r = await handleKeepPermanent(ctx, {
    runCli: mockOk('marked'), kanbanCliPath: '/x',
    allowlist: [ALLOWED], envCsv: '', timeoutMs: 1000,
  });
  assert.match(r.text, /marked/);
});
