import { test } from 'node:test';
import assert from 'node:assert';
import { formatBadUsage, formatCliReply, formatCliError, formatUnauthorized } from '../lib/format.js';

test('formatBadUsage per command', () => {
  assert.match(formatBadUsage('review'), /<gap-id>/);
  assert.match(formatBadUsage('postpone'), /1-365/);
  assert.match(formatBadUsage('unknownx'), /<args>/);
});

test('formatCliReply trims stdout', () => {
  assert.equal(formatCliReply('  hello\n', 'gap', 'review'), 'hello');
  assert.match(formatCliReply('', 'gap', 'review'), /no output/);
});

test('formatCliError truncates', () => {
  const long = 'x'.repeat(500);
  const r = formatCliError('g', long, 'dismiss');
  assert.ok(r.length < 350);
});

test('formatUnauthorized', () => {
  assert.match(formatUnauthorized(), /não autorizado/);
});
