// knowledge-sync-commands — OpenClaw plugin entry point.
//
// Registra 4 slash commands que invocam canonical.sh / pending.sh /
// status.sh da skill knowledge-sync via execFile, sem passar pelo LLM.
//
// Spec: bevox-knowledge/35_specs/2026-04-10-e1.1-fix-plugin-commands.md
// CLI fallback (canonical.sh direto no terminal) continua intacto.

import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { runCanonical, runPending, runStatus } from "./lib/exec.js";
import {
  formatExecResult,
  formatExecChain,
  formatPending,
  formatStatus,
} from "./lib/format.js";

export default definePluginEntry({
  id: "knowledge-sync-commands",
  name: "Knowledge Sync Commands",
  description:
    "Telegram slash commands for the knowledge-sync canonical approval flow.",

  register(api, { config } = {}) {
    api.registerCommand({
      name: "ks_approve",
      nativeNames: { default: "ks_approve" },
      description:
        "Approve and execute a pending canonical commit. Args: <short_id|last>",
      acceptsArgs: true,
      requireAuth: true,
      async handler(ctx) {
        const id = (ctx.args || "").trim() || "last";
        const approveResult = await runCanonical(config, "approve", id);
        if (!approveResult.ok) {
          return { text: formatExecResult(approveResult, `approve ${id}`) };
        }
        const executeResult = await runCanonical(config, "execute", id);
        return {
          text: formatExecChain(
            [approveResult, executeResult],
            [`approve ${id}`, `execute ${id}`],
          ),
        };
      },
    });

    api.registerCommand({
      name: "ks_reject",
      nativeNames: { default: "ks_reject" },
      description:
        "Reject a pending canonical commit. Args: <short_id|last> [reason]",
      acceptsArgs: true,
      requireAuth: true,
      async handler(ctx) {
        const args = (ctx.args || "").trim();
        if (!args) {
          return { text: "❌ Uso: /ks_reject <id|last> [reason]" };
        }
        const [id, ...reasonParts] = args.split(/\s+/);
        const reason = reasonParts.join(" ").trim();
        const result = await runCanonical(config, "reject", id, reason);
        return { text: formatExecResult(result, `reject ${id}`) };
      },
    });

    api.registerCommand({
      name: "ks_pending",
      nativeNames: { default: "ks_pending" },
      description: "List pending canonical approvals.",
      acceptsArgs: false,
      requireAuth: true,
      async handler() {
        const result = await runPending(config);
        return { text: formatPending(result) };
      },
    });

    api.registerCommand({
      name: "ks_status",
      nativeNames: { default: "ks_status" },
      description: "Show status of a canonical approval. Args: [short_id]",
      acceptsArgs: true,
      requireAuth: true,
      async handler(ctx) {
        const id = (ctx.args || "").trim() || undefined;
        const result = await runStatus(config, id);
        return { text: formatStatus(result) };
      },
    });
  },
});
