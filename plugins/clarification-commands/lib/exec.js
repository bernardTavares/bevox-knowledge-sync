// exec.js — wrapper execFile com DI opcional pra testes.
//
// runCli(args, opts, _execFile?) — se _execFile passado, usa-o (testes mockam).
// Opts: cliPath (obrigatório), timeoutMs (default 30s).
//
// Retorno uniforme: { ok: bool, stdout: string, stderr: string, code?: number,
//   signal?: string, message?: string }.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileP = promisify(execFile);

export const DEFAULTS = {
  timeoutMs: 30000,
  maxBuffer: 1024 * 1024, // 1MB
};

export async function runCli(args, opts = {}, _execFile = execFileP) {
  const { cliPath, timeoutMs = DEFAULTS.timeoutMs } = opts;
  if (!cliPath) {
    throw new Error('cliPath required in runCli opts');
  }
  try {
    const { stdout, stderr } = await _execFile(cliPath, args, {
      timeout: timeoutMs,
      encoding: 'utf-8',
      maxBuffer: DEFAULTS.maxBuffer,
    });
    return { ok: true, stdout: (stdout || '').trim(), stderr: (stderr || '').trim() };
  } catch (err) {
    return {
      ok: false,
      stdout: (err.stdout || '').toString().trim(),
      stderr: (err.stderr || '').toString().trim(),
      code: err.code,
      signal: err.signal,
      message: err.message,
    };
  }
}
