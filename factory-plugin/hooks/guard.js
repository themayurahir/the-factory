#!/usr/bin/env node
// Factory PreToolUse guard. Reads the hook JSON on stdin; prints a deny decision or nothing.
// ponytail: regex-level checks on the command text, not a shell parser. The headless allowlist is the
// first line of defence; this catches what an allowlisted command could still do.
const path = require('path');

const RUNS_ROOT = path.resolve(process.env.FACTORY_RUNS || 'D:/workspace/factory-runs');
// Agents that must report only (they return text; the conductor saves it).
const REPORT_ONLY = /(^|:)([a-z]+-reviewer|code-reviewer|performance-optimizer|gan-evaluator|silent-failure-hunter|type-design-analyzer|pr-test-analyzer|planner|architect|code-architect)$/;
const SECRET = /(^|[\s"'=\/\\])(\.env(\.(?!example\b|sample\b|template\b)[\w-]+)?|\.git-credentials|\.netrc|\.npmrc|\.pypirc|id_rsa\w*|id_ed25519\w*|credentials(\.json|\.ya?ml)?|[\w-]*\.pem|\.aws[\/\\][\w-]*|\.ssh[\/\\][\w-]*)(?=$|[\s"'\/\\;|&)])/i;
const FORCE_PUSH = /\bgit\b[^;&|]*\bpush\b[^;&|]*(\s--force(-with-lease)?\b|\s-f\b|\s\+\S)/;
const RM_RECURSIVE = /\brm\s+(-\w*[rR]\w*|--recursive)\b|\bRemove-Item\b[^;&|]*-Recurse|\b(rmdir|rd)\s+\/s\b/i;
const SHELL_WRITE = /(^|[^0-9&>])>{1,2}(?!&)|\btee\b|\bsed\s+-i\b|\b(rm|mv|cp|del|Set-Content|Out-File|Add-Content|Remove-Item|Move-Item|Copy-Item)\b/i;

function deny(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: `factory guard: ${reason}` },
  }));
  process.exit(0);
}

function inside(p, root) {
  const rel = path.relative(root, p);
  return rel !== '' && !rel.startsWith('..') && !path.isAbsolute(rel);
}

// rm -rf / Remove-Item -Recurse: every target must resolve strictly inside RUNS_ROOT.
function checkRecursiveDelete(cmd, cwd) {
  const cd = cmd.match(/^\s*cd\s+("([^"]+)"|'([^']+)'|(\S+))\s*&&/);
  const base = cd ? path.resolve(cwd, cd[2] || cd[3] || cd[4]) : cwd;
  const segment = cmd.slice(cmd.search(RM_RECURSIVE));
  const words = (segment.match(/"[^"]*"|'[^']*'|\S+/g) || []).slice(1)
    .filter((w) => !w.startsWith('-') && !/^\/s$/i.test(w))
    .map((w) => w.replace(/^["']|["']$/g, ''));
  if (!words.length) return deny('recursive delete without a target');
  for (const w of words) {
    if (/[;&|]/.test(w)) break;
    if (/^[~$*]|\*/.test(w)) return deny(`recursive delete of "${w}" (globs, ~ and variables are not allowed)`);
    if (!inside(path.resolve(base, w), RUNS_ROOT)) return deny(`recursive delete outside ${RUNS_ROOT}: "${w}"`);
  }
}

function main(input) {
  const tool = input.tool_name || '';
  const ti = input.tool_input || {};
  const agent = input.agent_type || '';
  const cwd = input.cwd || process.cwd();

  if (tool === 'AskUserQuestion' && process.env.FACTORY_AUTO === '1') {
    return deny('--auto run: do not ask; proceed with stated assumptions and record them.');
  }
  if (REPORT_ONLY.test(agent) && /^(Write|Edit|MultiEdit|NotebookEdit)$/.test(tool)) {
    return deny(`${agent} is report-only: return findings as text; the conductor saves them.`);
  }
  if (tool === 'Bash' || tool === 'PowerShell') {
    const cmd = String(ti.command || '');
    if (FORCE_PUSH.test(cmd)) return deny('force push is not allowed.');
    if (SECRET.test(cmd)) return deny('commands touching .env files or credentials are not allowed.');
    if (RM_RECURSIVE.test(cmd)) checkRecursiveDelete(cmd, cwd);
    if (REPORT_ONLY.test(agent) && SHELL_WRITE.test(cmd)) {
      return deny(`${agent} is report-only: no redirection, rm/mv/cp or in-place edits.`);
    }
    return;
  }
  if (/^(Read|Grep|Glob)$/.test(tool)) {
    const target = [ti.file_path, ti.path, ti.glob, tool === 'Glob' ? ti.pattern : ''].filter(Boolean).join(' ');
    if (SECRET.test(target)) return deny('reading .env files or credentials is not allowed.');
  }
}

let raw = '';
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  let input;
  try { input = JSON.parse(raw); } catch { process.exit(0); } // not our input; let the normal flow decide
  main(input);
  process.exit(0);
});
