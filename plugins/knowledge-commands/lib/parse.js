// parse.js — 7 parsers for /review /dismiss /postpone /accept /retire /keep /keep-permanent.

const GAP_ID_RE = /^[a-z0-9][a-z0-9\-]{1,80}$/;

export function parseGapId(s) {
  if (!s || typeof s !== 'string') return null;
  const t = s.trim();
  if (!GAP_ID_RE.test(t)) return null;
  return t;
}

function _firstToken(input) {
  if (!input || typeof input !== 'string') return [null, ''];
  const trimmed = input.replace(/^\s+/, '');
  const sp = trimmed.search(/\s/);
  if (sp < 0) return [trimmed.trim(), ''];
  return [trimmed.slice(0, sp).trim(), trimmed.slice(sp + 1).replace(/^\s+/, '')];
}

export function parseReviewArgs(input) {
  const [gid] = _firstToken(input);
  const id = parseGapId(gid);
  return id ? { gapId: id } : null;
}

export function parseDismissArgs(input) {
  return parseReviewArgs(input);
}

export function parsePostponeArgs(input) {
  const [gid, rest] = _firstToken(input);
  const id = parseGapId(gid);
  if (!id) return null;
  const [daysStr] = _firstToken(rest);
  const days = parseInt(daysStr, 10);
  if (!Number.isInteger(days) || days < 1 || days > 365) return null;
  return { gapId: id, days };
}

export function parseAcceptArgs(input) {
  const [gid, rest] = _firstToken(input);
  const id = parseGapId(gid);
  if (!id) return null;
  const [token] = _firstToken(rest);
  return { gapId: id, token: token || null };
}

export function parseRetireArgs(input) {
  return parseReviewArgs(input);
}

export function parseKeepArgs(input) {
  return parseReviewArgs(input);
}

export function parseKeepPermanentArgs(input) {
  return parseReviewArgs(input);
}
