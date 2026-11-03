import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  handlePending,
  handleShow,
  handleOverride,
  handleReject,
  handleRedraft,
} from '../lib/commands.js';

function makeCtx({ args = '', senderId = '123456789', to = null, messageThreadId = null } = {}) {
  return { args, senderId, channel: 'telegram', to, messageThreadId };
}

// Default mock notifier state: T-X has one pending clarification in chat -100test, thread 0.
function makeStateWithPending(taskId = 'T-X', chatId = '-100test', threadId = null) {
  return {
    schema_version: 2,
    notifications: {
      [`${taskId}-clr-1`]: {
        task_id: taskId,
        project: null,
        token_alias: 'openclaw-central',
        chat_id: chatId,
        thread_id: threadId,
        telegram_message_id: 100,
        sent_at: '2026-04-28T10:00:00Z',
        status: 'pending',
        resolved_at: null,
        resolved_via: null,
      },
    },
  };
}

// Empty state mock: no pending entries.
function makeEmptyState() {
  return { schema_version: 2, notifications: {} };
}

test('handlePending invokes CLI with [escalations, --json]', async () => {
  let captured;
  const runCliMock = async (args, opts) => {
    captured = { args, opts };
    return { ok: true, stdout: JSON.stringify({ escalations: [] }), stderr: '' };
  };
  const out = await handlePending(makeCtx(), { runCli: runCliMock, cliPath: '/fake' });
  assert.deepEqual(captured.args, ['escalations', '--json']);
  assert.equal(captured.opts.cliPath, '/fake');
  assert.match(out.text, /✅ Sem escalations/);
});

test('handleShow requires arg', async () => {
  const runCliMock = async () => { throw new Error('should not be called'); };
  const out = await handleShow(makeCtx({ args: '' }), { runCli: runCliMock, cliPath: '/fake' });
  assert.match(out.text, /❌ Uso:.*\/clr_show/);
});

test('handleShow invokes CLI with [show, ARG, --json]', async () => {
  let captured;
  const runCliMock = async (args) => {
    captured = args;
    return { ok: true, stdout: JSON.stringify({ clarification_ids: ['T-X-clr-1'] }), stderr: '' };
  };
  await handleShow(makeCtx({ args: 'T-X' }), { runCli: runCliMock, cliPath: '/fake' });
  assert.deepEqual(captured, ['show', 'T-X', '--json']);
});

test('handleOverride requires task_id + answer', async () => {
  const runCliMock = async () => { throw new Error('should not be called'); };
  const out = await handleOverride(makeCtx({ args: '' }), {
    runCli: runCliMock, cliPath: '/fake',
    loadNotifierState: makeEmptyState,
  });
  assert.match(out.text, /❌ Uso:.*\/clr_override/);

  const out2 = await handleOverride(makeCtx({ args: 'T-X' }), {
    runCli: runCliMock, cliPath: '/fake',
    loadNotifierState: makeEmptyState,
  });
  assert.match(out2.text, /❌ Uso:.*\/clr_override/);
});

test('handleOverride invokes CLI with override + --answer + --commit + --json + --actor', async () => {
  let captured;
  const runCliMock = async (args) => {
    captured = args;
    return { ok: true, stdout: JSON.stringify({
      clarification_id: 'T-X-clr-1', task_id: 'T-X', outcome: 'override_committed',
    }), stderr: '' };
  };
  // Provide state with pending entry and matching chat_id (null chat — skip validation)
  const stateWithNullChat = {
    schema_version: 2,
    notifications: {
      'T-X-clr-1': {
        task_id: 'T-X',
        project: null,
        token_alias: 'openclaw-central',
        chat_id: null, // null → cross-validation skips chat_id check
        thread_id: null,
        telegram_message_id: 100,
        sent_at: '2026-04-28T10:00:00Z',
        status: 'pending',
        resolved_at: null,
        resolved_via: null,
      },
    },
  };
  const out = await handleOverride(
    makeCtx({ args: 'T-X A resposta tem espacos e colon: detalhe', senderId: '123456789' }),
    { runCli: runCliMock, cliPath: '/fake', loadNotifierState: () => stateWithNullChat }
  );
  assert.equal(captured[0], 'override');
  assert.equal(captured[1], 'T-X');
  assert.ok(captured.includes('--answer'));
  const answerIdx = captured.indexOf('--answer');
  assert.equal(captured[answerIdx + 1], 'A resposta tem espacos e colon: detalhe');
  assert.ok(captured.includes('--commit'));
  assert.ok(captured.includes('--json'));
  const actorIdx = captured.indexOf('--actor');
  assert.equal(captured[actorIdx + 1], 'telegram:123456789');
  assert.match(out.text, /✅ Override commit T-X-clr-1/);
});

test('handleReject requires task_id + colon-formatted reason', async () => {
  const runCliMock = async () => { throw new Error('should not be called'); };
  const out = await handleReject(
    makeCtx({ args: 'T-X sem colon aqui' }),
    { runCli: runCliMock, cliPath: '/fake' }
  );
  assert.match(out.text, /❌ Uso:.*\/clr_reject/);
});

test('handleReject invokes CLI with reject-task + --reason + --commit + --json + --actor', async () => {
  let captured;
  const runCliMock = async (args) => {
    captured = args;
    return { ok: true, stdout: JSON.stringify({
      task_id: 'T-X', outcome: 'task_rejected', category: 'manual', reason: 'cleanup teste',
    }), stderr: '' };
  };
  const out = await handleReject(
    makeCtx({ args: 'T-X manual: cleanup teste', senderId: '123456789' }),
    { runCli: runCliMock, cliPath: '/fake' }
  );
  assert.equal(captured[0], 'reject-task');
  assert.equal(captured[1], 'T-X');
  const reasonIdx = captured.indexOf('--reason');
  assert.equal(captured[reasonIdx + 1], 'manual: cleanup teste');
  assert.ok(captured.includes('--commit'));
  assert.match(out.text, /❌ Reject commit T-X \(manual\)/);
});

test('handleRedraft invokes CLI with [redraft, ARG, --json, --actor]', async () => {
  let captured;
  const runCliMock = async (args) => {
    captured = args;
    return { ok: true, stdout: JSON.stringify({
      clarification_id: 'T-X-clr-3', outcome: 'safe',
    }), stderr: '' };
  };
  const out = await handleRedraft(
    makeCtx({ args: 'T-X', senderId: '123456789' }),
    { runCli: runCliMock, cliPath: '/fake' }
  );
  assert.equal(captured[0], 'redraft');
  assert.equal(captured[1], 'T-X');
  assert.ok(captured.includes('--json'));
  assert.match(out.text, /🔄 Redraft T-X.*outcome: safe/);
});

test('handleRedraft requires task_id', async () => {
  const runCliMock = async () => { throw new Error('should not be called'); };
  const out = await handleRedraft(makeCtx({ args: '' }), { runCli: runCliMock, cliPath: '/fake' });
  assert.match(out.text, /❌ Uso:.*\/clr_redraft/);
});

test('handler propagates CLI error via formatter', async () => {
  const runCliMock = async () => ({
    ok: false, code: 2,
    stdout: JSON.stringify({ ok: false, error: 'nao encontrada', code: 'CLARIFICATION_NOT_FOUND' }),
    stderr: '',
  });
  const stateWithNullChat = {
    schema_version: 2,
    notifications: {
      'T-X-clr-1': {
        task_id: 'T-X', status: 'pending', chat_id: null, thread_id: null,
        sent_at: '2026-04-28T10:00:00Z', telegram_message_id: 1,
      },
    },
  };
  const out = await handleOverride(
    makeCtx({ args: 'T-X A resposta' }),
    { runCli: runCliMock, cliPath: '/fake', loadNotifierState: () => stateWithNullChat }
  );
  assert.match(out.text, /❌ Override FALHOU/);
  assert.match(out.text, /CLARIFICATION_NOT_FOUND/);
});

// ─── handleOverride cross-validation tests ───────────────────────────────────

test('handleOverride returns "nenhuma pending" when no pending entry for task', async () => {
  const runCliMock = async () => { throw new Error('should not be called'); };
  const out = await handleOverride(
    makeCtx({ args: 'T-NONEXISTENT alguma resposta' }),
    { runCli: runCliMock, cliPath: '/fake', loadNotifierState: makeEmptyState }
  );
  assert.match(out.text, /Nenhuma clarification pendente para/);
  assert.match(out.text, /T-NONEXISTENT/);
});

test('handleOverride returns "já resolvida" when entry is not pending', async () => {
  const runCliMock = async () => { throw new Error('should not be called'); };
  const resolvedState = {
    schema_version: 2,
    notifications: {
      'T-X-clr-1': {
        task_id: 'T-X', status: 'resolved', chat_id: '-100test', thread_id: null,
        sent_at: '2026-04-28T10:00:00Z', telegram_message_id: 1,
      },
    },
  };
  const out = await handleOverride(
    makeCtx({ args: 'T-X alguma resposta' }),
    { runCli: runCliMock, cliPath: '/fake', loadNotifierState: () => resolvedState }
  );
  assert.match(out.text, /já foi resolvida/);
});

test('handleOverride returns chat mismatch error when chat_id differs', async () => {
  const runCliMock = async () => { throw new Error('should not be called'); };
  // entry in -100correct, command from -100wrong
  const state = makeStateWithPending('T-X', '-100correct', null);
  const out = await handleOverride(
    makeCtx({ args: 'T-X alguma resposta', to: 'telegram:-100wrong' }),
    { runCli: runCliMock, cliPath: '/fake', loadNotifierState: () => state }
  );
  assert.match(out.text, /chat\/thread diferente/);
});

test('handleOverride returns mismatch error when thread_id differs', async () => {
  const runCliMock = async () => { throw new Error('should not be called'); };
  const state = makeStateWithPending('T-X', '-100correct', 18);
  const out = await handleOverride(
    makeCtx({ args: 'T-X alguma resposta', to: 'telegram:-100correct', messageThreadId: 22 }),
    { runCli: runCliMock, cliPath: '/fake', loadNotifierState: () => state }
  );
  assert.match(out.text, /chat\/thread diferente/);
});

test('handleOverride proceeds when chat_id and thread_id match', async () => {
  let cliCalled = false;
  const runCliMock = async (args) => {
    cliCalled = true;
    return { ok: true, stdout: JSON.stringify({
      clarification_id: 'T-X-clr-1', task_id: 'T-X', outcome: 'override_committed',
    }), stderr: '' };
  };
  const state = makeStateWithPending('T-X', '-100correct', 18);
  const out = await handleOverride(
    makeCtx({ args: 'T-X alguma resposta', to: 'telegram:-100correct', messageThreadId: 18 }),
    { runCli: runCliMock, cliPath: '/fake', loadNotifierState: () => state }
  );
  assert.ok(cliCalled, 'CLI should have been called');
  assert.match(out.text, /✅ Override commit/);
});

test('handleOverride skips chat_id validation when ctx.to is null', async () => {
  // Bernard uses CLI or a context that doesn't provide ctx.to → skip validation
  let cliCalled = false;
  const runCliMock = async () => {
    cliCalled = true;
    return { ok: true, stdout: JSON.stringify({
      clarification_id: 'T-X-clr-1', task_id: 'T-X', outcome: 'override_committed',
    }), stderr: '' };
  };
  const state = makeStateWithPending('T-X', '-100correct', null);
  // ctx.to = null → extractChatId returns null → crossValidate skips chat_id check
  const out = await handleOverride(
    makeCtx({ args: 'T-X alguma resposta', to: null }),
    { runCli: runCliMock, cliPath: '/fake', loadNotifierState: () => state }
  );
  assert.ok(cliCalled, 'CLI should have been called when ctx.to is null');
  assert.match(out.text, /✅ Override commit/);
});
