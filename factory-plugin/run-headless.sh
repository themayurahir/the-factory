#!/usr/bin/env bash
# Headless /factory run.
#   ./run-headless.sh [--thorough] [--pr] [--oss] [--offices <list|none>] "<idea>" [budget_usd]
#   ./run-headless.sh --resume <run dir> [budget_usd]
# Never bypasses permissions: acceptEdits + a narrow allowlist; anything else is denied (no prompts, no stalls).
set -eu
PLUGIN="$(cd "$(dirname "$0")" && pwd)"
RUNS="${FACTORY_RUNS:-D:/workspace/factory-runs}"

FLAGS="" IDEA="" RESUME="" BUDGET=25
while [ $# -gt 0 ]; do
  case "$1" in
    --thorough|--pr|--oss) FLAGS="$FLAGS $1" ;;
    --offices) FLAGS="$FLAGS --offices $2"; shift ;;
    --resume) RESUME="$2"; shift ;;
    *) if [ -z "$IDEA" ] && [ -z "$RESUME" ]; then IDEA="$1"; else BUDGET="$1"; fi ;;
  esac
  shift
done
if [ -n "$RESUME" ]; then PROMPT="/factory:factory --auto$FLAGS --resume \"$RESUME\""
elif [ -n "$IDEA" ]; then PROMPT="/factory:factory --auto$FLAGS \"$IDEA\""
else echo "usage: $0 [--thorough] [--pr] [--oss] [--offices <list|none>] \"<idea>\" [budget] | --resume <dir> [budget]" >&2; exit 2; fi

# Shell command prefixes the stack profiles in stacks.md use. Each becomes a Bash(...) and a PowerShell(...) rule.
CMDS=(
  "python -m venv *" ".venv/Scripts/python*" ".venv/bin/python*"
  "npm init*" "npm install*" "npm ci*" "npm test*" "npm run *" "npm audit*"
  "npx tsc*" "npx eslint*" "npx vitest*" "npx playwright*" "npx prettier*" "npx create-next-app*" "node *"
  "go mod *" "go build*" "go test*" "go vet*" "go run *" "go get *" "gofmt *"
  "cargo init*" "cargo new*" "cargo add*" "cargo build*" "cargo test*" "cargo clippy*" "cargo fmt*" "cargo run*" "cargo check*" "cargo llvm-cov*"
  "gradle init*" "./gradlew *" "gradlew *"
  "mvn *" "./mvnw *" "java -jar *"
  "dotnet new*" "dotnet sln*" "dotnet add*" "dotnet restore*" "dotnet build*" "dotnet test*" "dotnet run*" "dotnet format*"
  "flutter create*" "flutter pub*" "flutter test*" "flutter analyze*" "flutter build*"
  "dart create*" "dart pub*" "dart test*" "dart analyze*" "dart format*" "dart run*"
  "cmake *" "ctest*" "./build/*"
  "ls *"  # conductor setup: is RUNS_ROOT/<slug> taken?
  # git only as `git -C <dir> <subcommand>`: Claude Code always denies `cd <dir> && git ...` compounds.
  "git -C * init*" "git -C * add *" "git -C * commit *" "git -C * status*" "git -C * diff*" "git -C * log*"
  "git -C * ls-files*" "git -C * rev-parse*" "git -C * remote get-url*"
)
case "$FLAGS" in *--pr*) CMDS+=("git -C * checkout -b factory/*" "git -C * push -u origin HEAD" "gh pr create*" "gh pr view*" "gh pr list*" "gh repo view*" "gh auth status*") ;; esac

ALLOW=("PowerShell(.venv\\Scripts\\python*)")
for c in "${CMDS[@]}"; do ALLOW+=("Bash($c)" "PowerShell($c)"); done
# Method files (skills/agents/commands) and the plugin itself live outside the runs folder: read-only access.
ALLOW+=("Read(~/.claude/commands/**)" "Read(~/.claude/agents/**)" "Read(~/.claude/.agents/skills/**)"
        "Read(~/.claude/skills/**)" "Read(~/.claude/plugins/cache/**)" "Read(//${PLUGIN#/}/**)"
        "Read(~/.claude/rules/**)" "Skill" "WebSearch" "WebFetch(domain:*)")

mkdir -p "$RUNS" && cd "$RUNS"
# One spelling for the conductor, guard.js and Claude's cwd: absolute, long names (no MAYURA~1), forward slashes.
RUNS="$(node -p 'require("fs").realpathSync.native(process.argv[1]).split("\\").join("/")' "$RUNS")"
BEFORE="$(ls -1 "$RUNS")" OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
FACTORY_AUTO=1 FACTORY_RUNS="$RUNS" CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=3600000 claude -p "$PROMPT" \
  --plugin-dir "$PLUGIN" \
  --permission-mode acceptEdits --permission-prompts none \
  --max-budget-usd "$BUDGET" --max-turns 200 \
  --output-format stream-json --verbose \
  --allowedTools "${ALLOW[@]}" | tee "$OUT"
RC=${PIPESTATUS[0]}

# Cost line from the stream's final result message (total_cost_usd). It replaces the conductor's "Cost: n/a" line in
# <run>/factory/report.md, else is appended; a resume adds its own line. No report.md yet (run stopped early): the
# line goes to run-log.md, which Deliver copies into the report. New run dir = the one new folder with a factory/.
RESUME="$RESUME" BEFORE="$BEFORE" node -e '
const fs = require("fs"), path = require("path");
const [log, runs] = process.argv.slice(1), resume = process.env.RESUME;
const die = (m) => { console.error("cost line not written: " + m); process.exit(1); };
const r = fs.readFileSync(log, "utf8").split("\n").filter((l) => l.includes("\"type\":\"result\""))
  .map((l) => { try { return JSON.parse(l); } catch { return {}; } }).filter((o) => o.type === "result").pop();
if (!r || typeof r.total_cost_usd !== "number") die("no result message with total_cost_usd");
const before = new Set(process.env.BEFORE.split("\n"));
const fresh = fs.readdirSync(runs).filter((d) => !before.has(d) && fs.existsSync(path.join(runs, d, "factory")));
if (!resume && fresh.length !== 1) die("expected one new run dir, found: " + (fresh.join(", ") || "none"));
const f = path.join(resume ? path.resolve(runs, resume) : path.join(runs, fresh[0]), "factory");
const line = `Cost: $${r.total_cost_usd.toFixed(2)} (headless, ${resume ? "resume" : "total"})`;
const report = path.join(f, "report.md");
if (fs.existsSync(report)) {
  const t = fs.readFileSync(report, "utf8"), na = /^Cost: n\/a[^\r\n]*/m;
  fs.writeFileSync(report, na.test(t) ? t.replace(na, () => line) : t.replace(/\s*$/, "\n") + line + "\n");
} else fs.appendFileSync(path.join(f, "run-log.md"), `- ${new Date().toISOString()} ${line}\n`);
console.error(line + " -> " + f);
' "$OUT" "$RUNS" || true
exit "$RC"
