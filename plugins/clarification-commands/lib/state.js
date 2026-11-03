// state.js — notifier-state.json schema v2 reader.
//
// Plugin reads notifier-state.json on each invocation (no caching).
// The only writer is the Python clarification-agent CLI subprocess
// (handle_reply → save_state_v2). Plugin NEVER writes to this file.
//
// Schema v2 shape (written by notifier.py after Tasks 4-7):
//   {
//     "schema_version": 2,
//     "notifications": {
//       "T-XXXX-clr-N": {
//         "task_id": "T-XXXX",
//         "project": "bevox-site" | null,
//         "token_alias": "project-bevox-site" | "openclaw-central" | null,
//         "chat_id": "-100xxxxx" | null,
//         "thread_id": 18 | null,
//         "telegram_message_id": 273,
//         "sent_at": "2026-04-28T11:36:01Z",
//         "status": "pending" | "resolved" | "failed" | "orphan",
//         "resolved_at": null | "...",
//         "resolved_via": null | "telegram_reply" | "slash_command" | "manual_cli"
//       }
//     }
//   }

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const DEFAULT_STATE_PATH = path.join(
  os.homedir(),
  '.openclaw',
  'clarification-agent',
  'notifier-state.json'
);

const EMPTY_STATE = { schema_version: 2, notifications: {} };

/**
 * Load notifier-state.json from disk.
 * Returns empty schema-v2 object if file is missing or unparseable.
 * Logs a structured warning if schema_version < 2 (migration not yet run).
 *
 * @param {string} [statePath] — override path (for testing)
 * @returns {{ schema_version: number, notifications: Record<string, object> }}
 */
export function loadNotifierState(statePath = DEFAULT_STATE_PATH) {
  try {
    const raw = fs.readFileSync(statePath, 'utf8');
    const data = JSON.parse(raw);
    if (data.schema_version !== 2) {
      // Migration not yet run — treat as empty. notifier.py migrates on next write.
      console.warn(
        JSON.stringify({
          level: 'warn',
          plugin: 'clarification-commands',
          event: 'notifier_state_schema_old',
          schema_version: data.schema_version ?? 'missing',
          message: 'notifier-state.json schema < v2; migration not yet run. Treating as empty.',
        })
      );
      return EMPTY_STATE;
    }
    return data;
  } catch (err) {
    if (err.code !== 'ENOENT') {
      console.warn(
        JSON.stringify({
          level: 'warn',
          plugin: 'clarification-commands',
          event: 'notifier_state_read_error',
          error: String(err.message),
        })
      );
    }
    return { ...EMPTY_STATE };
  }
}

/**
 * Find a clarification entry by its Telegram message_id.
 * Used for the swipe-reply path: lookup what clarification the user replied to.
 *
 * Note: The OpenClaw plugin SDK's inbound_claim hook does NOT expose
 * reply_to_message.message_id. This function is provided for completeness
 * and for future use if the SDK exposes this field, or for use from a
 * raw Telegram bot handler outside the plugin SDK.
 *
 * @param {{ notifications: Record<string, object> }} state
 * @param {number|string} messageId — Telegram message_id to look up
 * @returns {{ cid: string, [key: string]: unknown } | null}
 */
export function findEntryByMessageId(state, messageId) {
  const numericId = Number(messageId);
  for (const [cid, entry] of Object.entries(state.notifications || {})) {
    if (entry.telegram_message_id === numericId) {
      return { cid, ...entry };
    }
  }
  return null;
}

/**
 * Find the most recent PENDING clarification for a given task_id.
 * Used for the /clr_override <task> path.
 *
 * @param {{ notifications: Record<string, object> }} state
 * @param {string} taskId — e.g. "T-0105"
 * @returns {{ cid: string, [key: string]: unknown } | null}
 */
export function findPendingByTaskId(state, taskId) {
  let latest = null;
  for (const [cid, entry] of Object.entries(state.notifications || {})) {
    if (entry.task_id !== taskId) continue;
    if (entry.status !== 'pending') continue;
    if (!latest || (entry.sent_at ?? '') > (latest.sent_at ?? '')) {
      latest = { cid, ...entry };
    }
  }
  return latest;
}

/**
 * Cross-validate that an inbound command's chat/thread matches the
 * clarification entry's registered chat/thread.
 *
 * Returns null on success, or a string describing the validation failure.
 *
 * @param {object} entry — from findPendingByTaskId / findEntryByMessageId
 * @param {string|null} inboundChatId — e.g. "-100123456789"
 * @param {number|string|null} inboundThreadId — ctx.messageThreadId
 * @returns {string|null}
 */
export function crossValidate(entry, inboundChatId, inboundThreadId) {
  if (entry.chat_id != null && inboundChatId != null) {
    if (String(inboundChatId) !== String(entry.chat_id)) {
      return `chat_id mismatch: expected ${entry.chat_id}, got ${inboundChatId}`;
    }
  }
  const expectedThread = Number(entry.thread_id ?? 0);
  const gotThread = Number(inboundThreadId ?? 0);
  if (expectedThread !== gotThread) {
    return `thread_id mismatch: expected ${entry.thread_id ?? 0}, got ${inboundThreadId ?? 0}`;
  }
  return null; // all checks passed
}
