// parse.js — pure helpers for /unblock argument parsing.

const TASK_ID_RE = /^T-\d{4}$/;
const VALID_SUB = new Set(['pass', 'cancel', 'retry', 'answer']);

/**
 * Parse "<task-id> <pass|cancel|retry|answer> [note...]" raw arg string from Telegram.
 *
 * Returns { taskId, subcommand, note } on success, or null on bad input.
 * Note may contain newlines; everything after the first space following the
 * subcommand is treated as the note.
 *
 * For 'answer' subcommand, note is the answer text and MUST be non-empty.
 * For 'retry', note is ignored (optional).
 */
export function parseUnblockArgs(input) {
  if (!input || typeof input !== 'string') return null;
  const trimmed = input.replace(/^\s+/, '');
  if (!trimmed) return null;

  // Split into at most 3 segments: task-id, subcommand, rest.
  const firstSp = trimmed.indexOf(' ');
  if (firstSp < 0) return null;
  const taskId = trimmed.slice(0, firstSp).trim();
  if (!TASK_ID_RE.test(taskId)) return null;

  const afterTask = trimmed.slice(firstSp + 1).replace(/^\s+/, '');
  const secondSp = afterTask.search(/[\s\n]/);
  let subcommand;
  let note = '';
  if (secondSp < 0) {
    subcommand = afterTask.trim();
  } else {
    subcommand = afterTask.slice(0, secondSp).trim();
    note = afterTask.slice(secondSp + 1).replace(/^[ \t]+/, '');
  }
  if (!VALID_SUB.has(subcommand)) return null;

  // For 'answer', note must be non-empty (it IS the answer text)
  if (subcommand === 'answer' && !note.trim()) return null;

  return { taskId, subcommand, note };
}
