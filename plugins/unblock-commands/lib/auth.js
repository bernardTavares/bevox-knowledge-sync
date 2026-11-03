// auth.js — operator allowlist check for /unblock.

/**
 * isAuthorized(senderId, { allowlist, envCsv }) → bool
 *
 * - allowlist (array | null) takes precedence; if non-null array, sender must
 *   appear in it (string compare).
 * - envCsv is the OPENCLAW_GATEWAY_OPERATOR_IDS string (csv); used only when
 *   allowlist is null/undefined.
 * - Returns false when neither source yields a non-empty list.
 */
export function isAuthorized(senderId, { allowlist, envCsv } = {}) {
  const id = senderId == null ? '' : String(senderId);
  if (!id) return false;

  let list = null;
  if (Array.isArray(allowlist)) {
    list = allowlist.map((x) => String(x).trim()).filter(Boolean);
  } else if (typeof envCsv === 'string') {
    list = envCsv.split(',').map((x) => x.trim()).filter(Boolean);
  }
  if (!list || list.length === 0) return false;
  return list.includes(id);
}
