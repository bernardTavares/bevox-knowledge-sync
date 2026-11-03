import { test } from 'node:test';
import assert from 'node:assert';
import {
  parseGapId, parseReviewArgs, parseDismissArgs, parsePostponeArgs,
  parseAcceptArgs, parseRetireArgs, parseKeepArgs, parseKeepPermanentArgs,
} from '../lib/parse.js';

test('parseGapId accepts F1 + F4 IDs', () => {
  assert.equal(parseGapId('bevox-direct-a1b2c3d-spec'), 'bevox-direct-a1b2c3d-spec');
  assert.equal(parseGapId('bevox-direct-r-3f8a2b'), 'bevox-direct-r-3f8a2b');
  assert.equal(parseGapId(''), null);
  assert.equal(parseGapId('invalid id with spaces'), null);
});

test('parseReviewArgs', () => {
  assert.deepEqual(
    parseReviewArgs('bevox-direct-aaa-spec'),
    { gapId: 'bevox-direct-aaa-spec' },
  );
  assert.equal(parseReviewArgs(''), null);
});

test('parsePostponeArgs requires days int', () => {
  assert.deepEqual(
    parsePostponeArgs('bevox-direct-aaa-spec 7'),
    { gapId: 'bevox-direct-aaa-spec', days: 7 },
  );
  assert.equal(parsePostponeArgs('bevox-direct-aaa-spec'), null);
  assert.equal(parsePostponeArgs('bevox-direct-aaa-spec abc'), null);
  assert.equal(parsePostponeArgs('bevox-direct-aaa-spec 0'), null);
  assert.equal(parsePostponeArgs('bevox-direct-aaa-spec 400'), null);
});

test('parseAcceptArgs accepts optional token', () => {
  assert.deepEqual(
    parseAcceptArgs('bevox-direct-aaa-spec'),
    { gapId: 'bevox-direct-aaa-spec', token: null },
  );
  assert.deepEqual(
    parseAcceptArgs('bevox-direct-aaa-spec abc123XYZ'),
    { gapId: 'bevox-direct-aaa-spec', token: 'abc123XYZ' },
  );
});

test('parseDismissArgs', () => {
  assert.deepEqual(parseDismissArgs('gap-x'), { gapId: 'gap-x' });
});
test('parseRetireArgs', () => {
  assert.deepEqual(parseRetireArgs('gap-x'), { gapId: 'gap-x' });
});
test('parseKeepArgs', () => {
  assert.deepEqual(parseKeepArgs('gap-x'), { gapId: 'gap-x' });
});
test('parseKeepPermanentArgs', () => {
  assert.deepEqual(parseKeepPermanentArgs('gap-x'), { gapId: 'gap-x' });
});
