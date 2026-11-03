import { test } from 'node:test';
import assert from 'node:assert/strict';

import { isAuthorized } from '../lib/auth.js';

test('explicit allowlist accepts matching id', () => {
  assert.equal(isAuthorized('111', { allowlist: ['111', '222'] }), true);
  assert.equal(isAuthorized('999', { allowlist: ['111', '222'] }), false);
});

test('env fallback parsed from csv', () => {
  assert.equal(isAuthorized('333', { allowlist: null, envCsv: '111,333,222' }), true);
  assert.equal(isAuthorized('444', { allowlist: null, envCsv: '111,333,222' }), false);
});

test('config allowlist beats env when both present', () => {
  assert.equal(isAuthorized('111', { allowlist: ['111'], envCsv: '999' }), true);
  assert.equal(isAuthorized('999', { allowlist: ['111'], envCsv: '999' }), false);
});

test('returns false when no allowlist and no env', () => {
  assert.equal(isAuthorized('111', { allowlist: null, envCsv: '' }), false);
  assert.equal(isAuthorized('111', { allowlist: [], envCsv: undefined }), false);
});

test('coerces numeric senderId to string', () => {
  assert.equal(isAuthorized(111, { allowlist: ['111'] }), true);
});

test('trims and ignores empty csv entries', () => {
  assert.equal(isAuthorized('111', { allowlist: null, envCsv: ' 111 , , 222 ' }), true);
});
