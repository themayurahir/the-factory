#!/usr/bin/env bash
# Phase 0 Gate 1 eval (eval-harness style: capability eval, code-based grader, pass@1).
#   ./eval/run-gate.sh [budget_per_idea_usd] [extra run-headless flags, e.g. --thorough]
# Runs every idea in eval/ideas.txt through run-headless.sh, one after another, then grades each run:
#   PASS = the run's factory/verify.md ends with "VERIFY: PASS". Gate 1 passes at >= 3 of 5.
# Appends a dated section to eval/results.md. Expect roughly 25 min and $8-12 per idea at the default tier.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNS="${FACTORY_RUNS:-D:/workspace/factory-runs}"
BUDGET="${1:-25}"; shift || true
STAMP="$(date +%Y%m%d-%H%M)"
LOGS="$RUNS/eval-$STAMP"; mkdir -p "$LOGS"
ROWS="" PASSED=0 TOTAL=0

while IFS= read -r idea; do
  case "$idea" in ''|'#'*) continue ;; esac
  TOTAL=$((TOTAL + 1))
  log="$LOGS/idea-$TOTAL.jsonl"
  start=$(date +%s) before=$(ls -1 "$RUNS")
  "$HERE/../run-headless.sh" "$@" "$idea" "$BUDGET" > "$log" 2> "$LOGS/idea-$TOTAL.err"
  mins=$(( ($(date +%s) - start) / 60 ))
  result=$(grep '"type":"result"' "$log" | tail -1)
  cost=$(printf '%s' "$result" | grep -o '"total_cost_usd":[0-9.]*' | cut -d: -f2)
  # Run dir = the new folder with a factory/ inside (same rule as run-headless.sh; works for any FACTORY_RUNS).
  run="" verdict=FAIL verify="no verify.md"
  for d in $(ls -1 "$RUNS" | grep -vxF -f <(printf '%s\n' "$before")); do [ -d "$RUNS/$d/factory" ] && run=$d; done
  if [ -n "$run" ] && [ -f "$RUNS/$run/factory/verify.md" ]; then
    verify=$(grep -o 'VERIFY: .*' "$RUNS/$run/factory/verify.md" | tail -1)
    case "$verify" in "VERIFY: PASS"*) verdict=PASS; PASSED=$((PASSED + 1)) ;; esac
  fi
  ROWS="$ROWS| $TOTAL | $idea | $verdict | \`$verify\` | ${run:-none} | \$${cost:-?} | ${mins}m |
"
done < "$HERE/ideas.txt"

GATE=FAIL; [ "$PASSED" -ge 3 ] && GATE=PASS
{
  printf '\n## Run %s (budget $%s/idea, flags:%s)\n\n' "$STAMP" "$BUDGET" "${*:- none}"
  printf '| # | Idea | Result | Verify line | Run dir | Cost | Time |\n|---|---|---|---|---|---|---|\n%s' "$ROWS"
  printf '\npass@1: %s/%s. **Gate 1: %s** (needs >= 3/5). Logs: `%s`\n' "$PASSED" "$TOTAL" "$GATE" "$LOGS"
} >> "$HERE/results.md"
echo "Gate 1: $GATE ($PASSED/$TOTAL). See $HERE/results.md"
