// format.js — Telegram reply messages.

export function formatPassSuccess(taskId, operatorHandle) {
  return `✅ ${taskId} destravada como pass por ${operatorHandle || 'operador'}.`;
}

export function formatCancelSuccess(taskId, operatorHandle) {
  return `🚫 ${taskId} cancelada por ${operatorHandle || 'operador'}.`;
}

export function formatUnauthorized() {
  return '🚫 não autorizado';
}

export function formatBadUsage() {
  return '❌ Uso: /unblock <task-id> pass|cancel [nota]';
}

export function formatTaskNotFound(taskId) {
  return `❌ ${taskId}: não encontrada.`;
}

export function formatStaleTestRun(taskId, hours) {
  return `❌ ${taskId}: nenhum test_run inconclusivo nos últimos ${hours}h.`;
}

export function formatCliError(taskId, errMsg) {
  const safe = (errMsg || '').slice(0, 200);
  return `❌ ${taskId}: falha no kanban CLI — ${safe}`;
}

export function formatRetrySuccess(taskId, summary, operatorHandle) {
  const handle = operatorHandle ? `@${operatorHandle}` : 'operador';
  return `♻️ ${taskId} retry enviado para clarification-agent por ${handle}\n${summary}`;
}

export function formatAnswerSuccess(taskId, operatorHandle) {
  const handle = operatorHandle ? `@${operatorHandle}` : 'operador';
  return `✅ ${taskId} resposta registrada por ${handle}\nagente deve retomar`;
}

export function formatNeedsAnswerText() {
  return '❓ /unblock <task> answer <texto> — texto da resposta é obrigatório';
}
