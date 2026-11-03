import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  truncateForTelegram,
  formatPending,
  formatShow,
  formatOverride,
  formatReject,
  formatRedraft,
  formatError,
} from '../lib/format.js';

test('truncateForTelegram leaves short text alone', () => {
  assert.equal(truncateForTelegram('hello'), 'hello');
});

test('truncateForTelegram cuts at 4096 with suffix', () => {
  const big = 'x'.repeat(5000);
  const out = truncateForTelegram(big);
  assert.ok(out.length <= 4096);
  assert.ok(out.endsWith('(...)'));
});

test('truncateForTelegram honors custom hint suffix', () => {
  const big = 'x'.repeat(5000);
  const out = truncateForTelegram(big, { hint: ' ver mais: xxx' });
  assert.ok(out.length <= 4096);
  assert.ok(out.endsWith(' ver mais: xxx'));
});

test('formatPending with 3 escalations', () => {
  const result = { ok: true, stdout: JSON.stringify({
    escalations: [
      { clarification_id: 'T-0006-clr-2' },
      { clarification_id: 'T-0008-clr-1' },
      { clarification_id: 'T-0008-clr-2' },
    ],
  }) };
  const out = formatPending(result);
  assert.match(out, /📋 Escalations pendentes \(3\)/);
  assert.match(out, /• T-0006-clr-2/);
  assert.match(out, /• T-0008-clr-1/);
  assert.match(out, /• T-0008-clr-2/);
});

test('formatPending with 0 escalations shows empty state', () => {
  const result = { ok: true, stdout: JSON.stringify({ escalations: [] }) };
  assert.match(formatPending(result), /✅ Sem escalations pendentes/);
});

test('formatPending on CLI error falls back to error format', () => {
  const result = { ok: false, stderr: 'boom', code: 1 };
  const out = formatPending(result);
  assert.match(out, /❌/);
  assert.match(out, /boom/);
});

test('formatShow with cid returns question + answer snippets', () => {
  const result = { ok: true, stdout: JSON.stringify({
    clarification_id: 'T-0006-clr-2',
    question: 'Qual é a spec governante?',
    answer: 'Não posso responder. Confidence: unsafe.',
  }) };
  const out = formatShow(result);
  assert.match(out, /🔍 T-0006-clr-2/);
  assert.match(out, /Question:/);
  assert.match(out, /Answer:/);
  assert.match(out, /Qual é a spec/);
});

test('formatShow with task_id returns list of cids', () => {
  const result = { ok: true, stdout: JSON.stringify({
    clarification_ids: ['T-0006-clr-1', 'T-0006-clr-2'],
  }) };
  const out = formatShow(result);
  assert.match(out, /📋 T-0006/);
  assert.match(out, /• T-0006-clr-1/);
  assert.match(out, /• T-0006-clr-2/);
});

test('formatOverride success', () => {
  const result = { ok: true, stdout: JSON.stringify({
    clarification_id: 'T-0006-clr-2',
    task_id: 'T-0006',
    outcome: 'override_committed',
  }) };
  const out = formatOverride(result);
  assert.match(out, /✅ Override commit T-0006-clr-2/);
  assert.match(out, /Task T-0006 unblocked/);
});

test('formatOverride error with code', () => {
  const result = { ok: false, stdout: JSON.stringify({
    ok: false, error: 'nenhuma clarification pending pra T-XXXX',
    code: 'CLARIFICATION_NOT_FOUND',
  }), code: 2 };
  const out = formatOverride(result);
  assert.match(out, /❌ Override FALHOU/);
  assert.match(out, /CLARIFICATION_NOT_FOUND/);
  assert.match(out, /nenhuma clarification pending/);
});

test('formatReject success includes category + reason', () => {
  const result = { ok: true, stdout: JSON.stringify({
    task_id: 'T-0006',
    outcome: 'task_rejected',
    category: 'manual',
    reason: 'cleanup teste',
  }) };
  const out = formatReject(result);
  assert.match(out, /❌ Reject commit T-0006 \(manual\)/);
  assert.match(out, /cleanup teste/);
});

test('formatReject with INVALID_REJECT_CATEGORY error', () => {
  const result = { ok: false, stdout: JSON.stringify({
    ok: false, error: 'categoria foo invalida',
    code: 'INVALID_REJECT_CATEGORY',
  }) };
  const out = formatReject(result);
  assert.match(out, /❌ .*INVALID_REJECT_CATEGORY/);
});

test('formatRedraft with safe outcome', () => {
  const result = { ok: true, stdout: JSON.stringify({
    clarification_id: 'T-0006-clr-3', outcome: 'safe',
  }) };
  const out = formatRedraft(result, 'T-0006');
  assert.match(out, /🔄 Redraft T-0006/);
  assert.match(out, /T-0006-clr-3/);
  assert.match(out, /safe/);
});

test('formatRedraft with escalated outcome', () => {
  const result = { ok: true, stdout: JSON.stringify({
    clarification_id: 'T-0006-clr-3', outcome: 'escalated',
  }) };
  const out = formatRedraft(result, 'T-0006');
  assert.match(out, /🔄 Redraft T-0006.*escalated/s);
});

test('formatError generic fallback', () => {
  const result = { ok: false, stderr: 'timeout', code: 124, message: 'etimedout' };
  const out = formatError(result, 'test label');
  assert.match(out, /❌ test label FALHOU/);
  assert.match(out, /timeout/);
});
