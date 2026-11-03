// parse.js — pure helpers para parsear input de comandos e saída JSON do CLI.
//
// safeJsonParse: tolerante a stdout vazio / malformado (CLI pode falhar sem --json).
// parseRejectArgs: formato "<categoria>: <motivo>" — separador primeiro colon;
// demais colons preservados no reason.

export function safeJsonParse(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function parseRejectArgs(input) {
  if (!input || typeof input !== 'string') return null;
  const idx = input.indexOf(':');
  if (idx < 0) return null;
  const category = input.slice(0, idx).trim();
  const reason = input.slice(idx + 1).trim();
  if (!category || !reason) return null;
  return { category, reason };
}
