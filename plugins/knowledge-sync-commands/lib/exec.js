// exec.js — wrapper de child_process.execFile pra invocar scripts da
// skill knowledge-sync de forma controlada.
//
// Sempre passa por bash + path absoluto (não depende de PATH herdado).
// Timeout default 30s. Captura stdout/stderr crus pra preservar trilha
// auditável; quem chama decide formatação.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import os from "node:os";
import path from "node:path";

const execFileP = promisify(execFile);

const DEFAULT_SCRIPTS_DIR = path.join(
  os.homedir(),
  ".openclaw",
  "skills",
  "knowledge-sync",
  "scripts",
);
const DEFAULT_TIMEOUT_MS = 30000;

function getScriptsDir(config) {
  return config?.scriptsDir || DEFAULT_SCRIPTS_DIR;
}

function getTimeoutMs(config) {
  return config?.execTimeoutMs || DEFAULT_TIMEOUT_MS;
}

async function runScript(config, scriptName, args = []) {
  const scriptsDir = getScriptsDir(config);
  const scriptPath = path.join(scriptsDir, scriptName);
  const timeout = getTimeoutMs(config);
  try {
    const { stdout, stderr } = await execFileP("bash", [scriptPath, ...args], {
      timeout,
      encoding: "utf-8",
      maxBuffer: 1024 * 1024,
    });
    return { ok: true, stdout: (stdout || "").trim(), stderr: (stderr || "").trim() };
  } catch (err) {
    return {
      ok: false,
      stdout: (err.stdout || "").toString().trim(),
      stderr: (err.stderr || "").toString().trim(),
      code: err.code,
      signal: err.signal,
      message: err.message,
    };
  }
}

export async function runCanonical(config, action, id, reason) {
  const args = [action, id];
  if (action === "reject" && reason) args.push(reason);
  return runScript(config, "canonical.sh", args);
}

export async function runPending(config) {
  return runScript(config, "pending.sh", ["--json"]);
}

export async function runStatus(config, id) {
  const args = id ? [id, "--json"] : ["--json"];
  return runScript(config, "status.sh", args);
}
