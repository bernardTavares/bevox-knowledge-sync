// format.js — formatadores pra Telegram. Saída texto curto + emoji
// para distinguir success/error visualmente.
//
// Princípios:
// - preserva stdout/stderr crus do canonical.sh (trilha auditável)
// - não inventa significado; se script falhar, mostra exit code + mensagem
// - usa apenas caracteres seguros pra Telegram (sem markdown que possa quebrar)

function safeJsonParse(raw) {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function formatExecResult(result, label) {
  if (result.ok) {
    return `✅ ${label}\n${result.stdout || "(sem output)"}`;
  }
  const errMsg = result.stderr || result.stdout || result.message || "(sem detalhe)";
  const codeNote = result.code !== undefined ? ` (exit ${result.code})` : "";
  return `❌ ${label} FALHOU${codeNote}\n${errMsg}`;
}

export function formatExecChain(results, labels) {
  return results
    .map((r, i) => formatExecResult(r, labels[i] || "step"))
    .join("\n\n");
}

export function formatPending(result) {
  if (!result.ok) {
    return formatExecResult(result, "pending");
  }
  const json = safeJsonParse(result.stdout);
  if (!json) {
    return `📋 pending\n${result.stdout || "(saída vazia)"}`;
  }
  const items = json.pending || json.approvals || [];
  if (items.length === 0) {
    return "📋 Nenhum approval pendente.";
  }
  const lines = items.map((it) => {
    const id = it.short_id || it.approval_id || it.id || "?";
    const msg = it.message || it.title || it.commit_message || "(sem mensagem)";
    return `  • ${id} — ${msg}`;
  });
  return `📋 ${items.length} pendente(s):\n${lines.join("\n")}`;
}

export function formatStatus(result) {
  if (!result.ok) {
    return formatExecResult(result, "status");
  }
  const json = safeJsonParse(result.stdout);
  if (!json) {
    return `🔎 status\n${result.stdout || "(saída vazia)"}`;
  }
  const id = json.short_id || json.approval_id || "?";
  const status = json.status || "?";
  const extra = json.message || json.commit_message || "";
  return `🔎 ${id}: ${status}${extra ? "\n" + extra : ""}`;
}
