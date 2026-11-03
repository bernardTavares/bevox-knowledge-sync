import { test } from 'node:test';
import assert from 'node:assert/strict';

import { runCli, DEFAULTS } from '../lib/exec.js';

// runCli é injetável via _execFile mock (3º argumento opcional pra teste)
test('runCli success returns ok=true with stdout/stderr', async () => {
  const mockExec = async (cmd, args, opts) => {
    assert.equal(cmd, '/fake/cli.sh');
    assert.deepEqual(args, ['show', 'T-0006', '--json']);
    return { stdout: '{"clarification_ids":[]}', stderr: '' };
  };
  const out = await runCli(['show', 'T-0006', '--json'], {
    cliPath: '/fake/cli.sh',
  }, mockExec);
  assert.equal(out.ok, true);
  assert.equal(out.stdout, '{"clarification_ids":[]}');
  assert.equal(out.stderr, '');
});

test('runCli failure captures stdout+stderr+code', async () => {
  const err = Object.assign(new Error('non-zero exit'), {
    code: 2, stdout: '{"ok":false,"code":"CLARIFICATION_NOT_FOUND"}', stderr: '',
  });
  const mockExec = async () => { throw err; };
  const out = await runCli(['override', 'T-XXX', '--answer', 'x', '--commit', '--json'], {
    cliPath: '/fake/cli.sh',
  }, mockExec);
  assert.equal(out.ok, false);
  assert.equal(out.code, 2);
  assert.ok(out.stdout.includes('CLARIFICATION_NOT_FOUND'));
});

test('runCli default timeout is DEFAULTS.timeoutMs', async () => {
  let capturedOpts;
  const mockExec = async (_cmd, _args, opts) => {
    capturedOpts = opts;
    return { stdout: '{}', stderr: '' };
  };
  await runCli(['escalations', '--json'], { cliPath: '/fake' }, mockExec);
  assert.equal(capturedOpts.timeout, DEFAULTS.timeoutMs);
  assert.equal(capturedOpts.encoding, 'utf-8');
});

test('runCli custom timeout overrides default', async () => {
  let capturedOpts;
  const mockExec = async (_cmd, _args, opts) => {
    capturedOpts = opts;
    return { stdout: '{}', stderr: '' };
  };
  await runCli(['escalations', '--json'], {
    cliPath: '/fake', timeoutMs: 5000,
  }, mockExec);
  assert.equal(capturedOpts.timeout, 5000);
});

test('runCli throws if cliPath missing', async () => {
  await assert.rejects(
    () => runCli(['x'], {}, async () => ({ stdout: '', stderr: '' })),
    /cliPath required/,
  );
});
