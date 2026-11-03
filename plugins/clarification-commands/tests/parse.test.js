import { test } from 'node:test';
import assert from 'node:assert/strict';

import { safeJsonParse, parseRejectArgs } from '../lib/parse.js';

test('safeJsonParse returns parsed object for valid JSON', () => {
  const out = safeJsonParse('{"a":1}');
  assert.deepEqual(out, { a: 1 });
});

test('safeJsonParse returns null for empty string', () => {
  assert.equal(safeJsonParse(''), null);
  assert.equal(safeJsonParse(null), null);
  assert.equal(safeJsonParse(undefined), null);
});

test('safeJsonParse returns null for garbage', () => {
  assert.equal(safeJsonParse('not json'), null);
  assert.equal(safeJsonParse('{broken'), null);
});

test('parseRejectArgs extracts category and reason (colon separator)', () => {
  const out = parseRejectArgs('task_malformed: payload vazio');
  assert.deepEqual(out, { category: 'task_malformed', reason: 'payload vazio' });
});

test('parseRejectArgs trims whitespace around both parts', () => {
  const out = parseRejectArgs('  manual  :   cleanup teste  ');
  assert.deepEqual(out, { category: 'manual', reason: 'cleanup teste' });
});

test('parseRejectArgs returns null when no colon present', () => {
  assert.equal(parseRejectArgs('task_malformed sem colon'), null);
  assert.equal(parseRejectArgs(''), null);
});

test('parseRejectArgs preserves colons in reason body', () => {
  const out = parseRejectArgs('inexecutable: missing dep: foo::bar');
  assert.equal(out.category, 'inexecutable');
  assert.equal(out.reason, 'missing dep: foo::bar');
});
