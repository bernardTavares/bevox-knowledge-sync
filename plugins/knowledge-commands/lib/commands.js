// commands.js — 7 handlers: parse → auth → execFile Python CLI → reply.

import { isAuthorized } from './auth.js';
import {
  parseReviewArgs, parseDismissArgs, parsePostponeArgs, parseAcceptArgs,
  parseRetireArgs, parseKeepArgs, parseKeepPermanentArgs,
} from './parse.js';
import {
  formatUnauthorized, formatBadUsage, formatCliReply, formatCliError,
} from './format.js';

async function _dispatchSimple(ctx, deps, name, parser, cliArgs) {
  const { runCli, kanbanCliPath, allowlist, envCsv, timeoutMs } = deps;
  if (!isAuthorized(ctx.senderId, { allowlist, envCsv })) {
    return { text: formatUnauthorized() };
  }
  const parsed = parser(ctx.args || '');
  if (!parsed) return { text: formatBadUsage(name) };
  const args = cliArgs(parsed);
  const r = await runCli(args, { cliPath: kanbanCliPath, timeoutMs });
  if (!r.ok) {
    return { text: formatCliError(parsed.gapId, r.stderr || r.message, name) };
  }
  return { text: formatCliReply(r.stdout, parsed.gapId, name) };
}

export async function handleReview(ctx, deps) {
  return _dispatchSimple(ctx, deps, 'review', parseReviewArgs,
    (p) => ['knowledge', 'review', p.gapId]);
}

export async function handleDismiss(ctx, deps) {
  return _dispatchSimple(ctx, deps, 'dismiss', parseDismissArgs,
    (p) => ['knowledge', 'dismiss', p.gapId]);
}

export async function handlePostpone(ctx, deps) {
  return _dispatchSimple(ctx, deps, 'postpone', parsePostponeArgs,
    (p) => ['knowledge', 'postpone', p.gapId, String(p.days)]);
}

export async function handleAccept(ctx, deps) {
  return _dispatchSimple(ctx, deps, 'accept', parseAcceptArgs,
    (p) => p.token
      ? ['knowledge', 'accept', p.gapId, p.token]
      : ['knowledge', 'accept', p.gapId]);
}

export async function handleRetire(ctx, deps) {
  return _dispatchSimple(ctx, deps, 'retire', parseRetireArgs,
    (p) => ['knowledge', 'retire', p.gapId]);
}

export async function handleKeep(ctx, deps) {
  return _dispatchSimple(ctx, deps, 'keep', parseKeepArgs,
    (p) => ['knowledge', 'keep', p.gapId]);
}

export async function handleKeepPermanent(ctx, deps) {
  return _dispatchSimple(ctx, deps, 'keep-permanent', parseKeepPermanentArgs,
    (p) => ['knowledge', 'keep-permanent', p.gapId]);
}
