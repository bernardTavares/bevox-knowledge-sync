import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  loadNotifierState,
  findEntryByMessageId,
  findPendingByTaskId,
  crossValidate,
} from '../lib/state.js';

// ─── helpers ────────────────────────────────────────────────────────────────

function tmpFile(content = '') {
  const p = path.join(os.tmpdir(), `state-test-${process.pid}-${Date.now()}.json`);
  fs.writeFileSync(p, content, 'utf8');
  return p;
}

function cleanup(p) {
  try { fs.unlinkSync(p); } catch { /* ignore */ }
}

const V2_STATE = {
  schema_version: 2,
  notifications: {
    'T-0105-clr-1': {
      task_id: 'T-0105',
      project: 'bevox-site',
      token_alias: 'project-bevox-site',
      chat_id: '-100999888',
      thread_id: 18,
      telegram_message_id: 273,
      sent_at: '2026-04-28T11:36:01Z',
      status: 'pending',
      resolved_at: null,
      resolved_via: null,
    },
    'T-0105-clr-2': {
      task_id: 'T-0105',
      project: 'bevox-site',
      token_alias: 'project-bevox-site',
      chat_id: '-100999888',
      thread_id: 18,
      telegram_message_id: 280,
      sent_at: '2026-04-28T12:00:00Z',
      status: 'pending',
      resolved_at: null,
      resolved_via: null,
    },
    'T-0024-clr-4': {
      task_id: 'T-0024',
      project: null,
      token_alias: 'openclaw-central',
      chat_id: '-100111222',
      thread_id: null,
      telegram_message_id: 100,
      sent_at: '2026-04-27T10:00:00Z',
      status: 'resolved',
      resolved_at: '2026-04-27T11:00:00Z',
      resolved_via: 'slash_command',
    },
  },
};

// ─── loadNotifierState ───────────────────────────────────────────────────────

test('loadNotifierState returns empty object when file missing', () => {
  const missing = '/tmp/does-not-exist-clarification-99999.json';
  const state = loadNotifierState(missing);
  assert.equal(state.schema_version, 2);
  assert.deepEqual(state.notifications, {});
});

test('loadNotifierState reads and returns valid v2 state', () => {
  const p = tmpFile(JSON.stringify(V2_STATE));
  try {
    const state = loadNotifierState(p);
    assert.equal(state.schema_version, 2);
    assert.ok('T-0105-clr-1' in state.notifications);
    assert.equal(state.notifications['T-0105-clr-1'].telegram_message_id, 273);
  } finally { cleanup(p); }
});

test('loadNotifierState returns empty when schema_version != 2 (migration not run)', () => {
  const v1 = JSON.stringify({ schema_version: 1, notifications: { 'T-X-clr-1': {} } });
  const p = tmpFile(v1);
  try {
    const state = loadNotifierState(p);
    assert.equal(state.schema_version, 2);
    assert.deepEqual(state.notifications, {});
  } finally { cleanup(p); }
});

test('loadNotifierState returns empty on malformed JSON', () => {
  const p = tmpFile('{broken json');
  try {
    const state = loadNotifierState(p);
    assert.deepEqual(state.notifications, {});
  } finally { cleanup(p); }
});

// ─── findEntryByMessageId ────────────────────────────────────────────────────

test('findEntryByMessageId finds entry by numeric message_id', () => {
  const entry = findEntryByMessageId(V2_STATE, 273);
  assert.ok(entry !== null);
  assert.equal(entry.cid, 'T-0105-clr-1');
  assert.equal(entry.task_id, 'T-0105');
  assert.equal(entry.token_alias, 'project-bevox-site');
});

test('findEntryByMessageId finds entry by string message_id (coerced to number)', () => {
  const entry = findEntryByMessageId(V2_STATE, '273');
  assert.ok(entry !== null);
  assert.equal(entry.cid, 'T-0105-clr-1');
});

test('findEntryByMessageId returns null for unknown message_id', () => {
  const entry = findEntryByMessageId(V2_STATE, 9999);
  assert.equal(entry, null);
});

test('findEntryByMessageId returns null for empty state', () => {
  const entry = findEntryByMessageId({ schema_version: 2, notifications: {} }, 273);
  assert.equal(entry, null);
});

// ─── findPendingByTaskId ─────────────────────────────────────────────────────

test('findPendingByTaskId returns most recent pending entry', () => {
  // T-0105 has clr-1 (sent earlier) and clr-2 (sent later), both pending
  const entry = findPendingByTaskId(V2_STATE, 'T-0105');
  assert.ok(entry !== null);
  // clr-2 has later sent_at
  assert.equal(entry.cid, 'T-0105-clr-2');
});

test('findPendingByTaskId returns null when all entries resolved', () => {
  const entry = findPendingByTaskId(V2_STATE, 'T-0024');
  assert.equal(entry, null);
});

test('findPendingByTaskId returns null for unknown task_id', () => {
  const entry = findPendingByTaskId(V2_STATE, 'T-9999');
  assert.equal(entry, null);
});

test('findPendingByTaskId ignores non-pending statuses', () => {
  const state = {
    schema_version: 2,
    notifications: {
      'T-X-clr-1': { task_id: 'T-X', status: 'resolved', sent_at: '2026-04-28T10:00:00Z' },
      'T-X-clr-2': { task_id: 'T-X', status: 'orphan', sent_at: '2026-04-28T11:00:00Z' },
      'T-X-clr-3': { task_id: 'T-X', status: 'pending', sent_at: '2026-04-28T09:00:00Z' },
    },
  };
  const entry = findPendingByTaskId(state, 'T-X');
  assert.equal(entry.cid, 'T-X-clr-3'); // only pending one
});

// ─── crossValidate ───────────────────────────────────────────────────────────

test('crossValidate returns null when chat_id and thread_id match', () => {
  const entry = { cid: 'T-X-clr-1', chat_id: '-100999888', thread_id: 18 };
  const result = crossValidate(entry, '-100999888', 18);
  assert.equal(result, null);
});

test('crossValidate returns error string on chat_id mismatch', () => {
  const entry = { cid: 'T-X-clr-1', chat_id: '-100999888', thread_id: 18 };
  const result = crossValidate(entry, '-100111111', 18);
  assert.ok(typeof result === 'string');
  assert.match(result, /chat_id mismatch/);
});

test('crossValidate returns error string on thread_id mismatch', () => {
  const entry = { cid: 'T-X-clr-1', chat_id: '-100999888', thread_id: 18 };
  const result = crossValidate(entry, '-100999888', 22);
  assert.ok(typeof result === 'string');
  assert.match(result, /thread_id mismatch/);
});

test('crossValidate treats null thread_id and 0 as equivalent', () => {
  const entry = { cid: 'T-X-clr-1', chat_id: '-100999888', thread_id: null };
  const result = crossValidate(entry, '-100999888', null);
  assert.equal(result, null);
});

test('crossValidate treats null thread_id and 0 as equivalent (entry side)', () => {
  const entry = { cid: 'T-X-clr-1', chat_id: '-100999888', thread_id: 0 };
  const result = crossValidate(entry, '-100999888', null);
  assert.equal(result, null);
});

test('crossValidate skips chat_id check when entry.chat_id is null (orphan entry)', () => {
  const entry = { cid: 'T-X-clr-1', chat_id: null, thread_id: 0 };
  const result = crossValidate(entry, '-100anything', null);
  assert.equal(result, null); // cannot validate → pass through
});

test('crossValidate compares chat_id as strings (numeric comparison would fail)', () => {
  // chat_id is often a large negative number; string comparison must work
  const entry = { cid: 'T-X-clr-1', chat_id: '-1001234567890', thread_id: 0 };
  const result = crossValidate(entry, '-1001234567890', 0);
  assert.equal(result, null);
});
