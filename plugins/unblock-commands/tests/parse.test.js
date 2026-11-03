import { test } from 'node:test';
import assert from 'node:assert/strict';

import { parseUnblockArgs } from '../lib/parse.js';

test('parses pass without note', () => {
  const r = parseUnblockArgs('T-0155 pass');
  assert.deepEqual(r, { taskId: 'T-0155', subcommand: 'pass', note: '' });
});

test('parses pass with note', () => {
  const r = parseUnblockArgs('T-0155 pass validei manualmente no servidor');
  assert.deepEqual(r, {
    taskId: 'T-0155', subcommand: 'pass', note: 'validei manualmente no servidor',
  });
});

test('parses cancel with reason', () => {
  const r = parseUnblockArgs('T-0099 cancel perdeu propósito após decisão de produto');
  assert.deepEqual(r, {
    taskId: 'T-0099', subcommand: 'cancel',
    note: 'perdeu propósito após decisão de produto',
  });
});

test('rejects bad task id format', () => {
  assert.equal(parseUnblockArgs('foo pass'), null);
  assert.equal(parseUnblockArgs('T-12 pass'), null);  // 4 digits required
  assert.equal(parseUnblockArgs('T-12345 pass'), null);
});

test('rejects unknown subcommand', () => {
  assert.equal(parseUnblockArgs('T-0001 bogus'), null);
  assert.equal(parseUnblockArgs('T-0001'), null);
  assert.equal(parseUnblockArgs(''), null);
});

test('preserves multiline note', () => {
  const r = parseUnblockArgs('T-0001 pass linha1\nlinha2');
  assert.equal(r.note, 'linha1\nlinha2');
});

test('parses retry sub-action', () => {
  const r = parseUnblockArgs('T-0001 retry');
  assert.deepEqual(r, { taskId: 'T-0001', subcommand: 'retry', note: '' });
});

test('parses retry with extra text (ignored)', () => {
  const r = parseUnblockArgs('T-0001 retry alguns comentários');
  assert.deepEqual(r, { taskId: 'T-0001', subcommand: 'retry', note: 'alguns comentários' });
});

test('parses answer with text', () => {
  const r = parseUnblockArgs('T-0001 answer texto da resposta longo');
  assert.deepEqual(r, { taskId: 'T-0001', subcommand: 'answer', note: 'texto da resposta longo' });
});

test('rejects answer without text', () => {
  const r = parseUnblockArgs('T-0001 answer');
  assert.equal(r, null);
});

test('rejects answer with only whitespace', () => {
  const r = parseUnblockArgs('T-0001 answer   \n  ');
  assert.equal(r, null);
});
