// format.js — formatadores de resposta pro chat Telegram.
//
// Princípios:
// - Texto plano, sem markdown pesado (consistente com wave-2).
// - Fail-safe: CLI stdout vazio ou malformado ainda produz msg legível.
// - Respeita limite 4096 chars do Telegram via truncateForTelegram.

import { safeJsonParse } from './parse.js';

const TELEGRAM_LIMIT = 4096;

export function truncateForTelegram(text, { hint = '(...)' } = {}) {
  if (!text) return '';
  if (text.length <= TELEGRAM_LIMIT) return text;
  const budget = TELEGRAM_LIMIT - hint.length;
  return text.slice(0, Math.max(0, budget)) + hint;
}

export function formatError(result, label) {
  const parsed = safeJsonParse(result?.stdout);
  const codeFromJson = parsed?.code;
  const errFromJson = parsed?.error;
  const stderr = (result?.stderr || '').trim();
  const msg = errFromJson || stderr || result?.message || '(sem detalhe)';
  const codeNote = codeFromJson
    ? ` (${codeFromJson})`
    : (result?.code !== undefined ? ` (exit ${result.code})` : '');
  return truncateForTelegram(`❌ ${label} FALHOU${codeNote}\n${msg}`);
}

export function formatPending(result) {
  if (!result.ok) return formatError(result, 'pending');
  const json = safeJsonParse(result.stdout);
  const escalations = json?.escalations;
  if (!Array.isArray(escalations)) {
    return truncateForTelegram(`📋 pending (output nao parseavel)\n${result.stdout || ''}`);
  }
  if (escalations.length === 0) {
    return '✅ Sem escalations pendentes.';
  }
  const lines = escalations.map(e => `• ${e.clarification_id}`);
  return truncateForTelegram(
    `📋 Escalations pendentes (${escalations.length}):\n${lines.join('\n')}`
  );
}

export function formatShow(result) {
  if (!result.ok) return formatError(result, 'show');
  const json = safeJsonParse(result.stdout);
  if (!json) {
    return truncateForTelegram(`🔍 show (output nao parseavel)\n${result.stdout || ''}`);
  }
  // show <task_id> → retorna { clarification_ids: [...] }
  if (Array.isArray(json.clarification_ids)) {
    const taskId = json.clarification_ids[0]?.replace(/-clr-\d+$/, '') || '';
    const lines = json.clarification_ids.map(c => `• ${c}`);
    return truncateForTelegram(
      `📋 ${taskId} (${json.clarification_ids.length} clarifications):\n${lines.join('\n')}`
    );
  }
  // show <cid> → retorna { clarification_id, question, answer }
  const cid = json.clarification_id || '';
  const qSnippet = (json.question || '(sem question)').slice(0, 500);
  const aSnippet = (json.answer || '(sem answer)').slice(0, 500);
  const body = [
    `🔍 ${cid}`,
    'Question:',
    qSnippet,
    '',
    'Answer:',
    aSnippet,
  ].join('\n');
  return truncateForTelegram(
    body,
    { hint: `\n(...) Ver detalhe: vox clarification show ${cid}` }
  );
}

export function formatOverride(result) {
  if (!result.ok) return formatError(result, 'Override');
  const json = safeJsonParse(result.stdout);
  if (!json) return truncateForTelegram(`✅ Override (output nao parseavel)\n${result.stdout || ''}`);
  const cid = json.clarification_id || '(cid?)';
  const taskId = json.task_id || cid.replace(/-clr-\d+$/, '');
  return `✅ Override commit ${cid}\nTask ${taskId} unblocked.`;
}

export function formatReject(result) {
  if (!result.ok) return formatError(result, 'Reject');
  const json = safeJsonParse(result.stdout);
  if (!json) return truncateForTelegram(`❌ Reject (output nao parseavel)\n${result.stdout || ''}`);
  const taskId = json.task_id || '(task?)';
  const category = json.category || '(categoria?)';
  const reason = json.reason || '';
  return `❌ Reject commit ${taskId} (${category})\n  motivo: "${reason}"`;
}

export function formatRedraft(result, requestedTaskId) {
  if (!result.ok) return formatError(result, 'Redraft');
  const json = safeJsonParse(result.stdout);
  if (!json) return truncateForTelegram(`🔄 Redraft (output nao parseavel)\n${result.stdout || ''}`);
  const cid = json.clarification_id || '(cid?)';
  const outcome = json.outcome || '(outcome?)';
  return `🔄 Redraft ${requestedTaskId} → ${cid} (outcome: ${outcome})`;
}
