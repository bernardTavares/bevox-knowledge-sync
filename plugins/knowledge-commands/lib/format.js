// format.js — Telegram reply formatters.

export function formatUnauthorized() {
  return '🚫 não autorizado';
}

export function formatBadUsage(command) {
  const usage = {
    review: '/review <gap-id>',
    dismiss: '/dismiss <gap-id>',
    postpone: '/postpone <gap-id> <N>  (N: 1-365)',
    accept: '/accept <gap-id> [token]',
    retire: '/retire <gap-id>',
    keep: '/keep <gap-id>',
    'keep-permanent': '/keep-permanent <gap-id>',
  };
  return `❌ Uso: ${usage[command] || `/${command} <args>`}`;
}

export function formatCliReply(stdout, taskId, command) {
  return (stdout || '').trim() || `(no output) /${command} ${taskId}`;
}

export function formatCliError(taskId, errMsg, command) {
  const safe = (errMsg || '').slice(0, 300);
  return `❌ /${command} ${taskId}: erro CLI — ${safe}`;
}
