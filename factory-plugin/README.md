# factory (Phase 0, v0.2)

Claude Code plugin. `/factory "<idea>"` turns a vague idea into a tested, reviewed repo under
`D:/workspace/factory-runs/<slug>/`, with every stage's artifact in `<slug>/factory/`.

Stages (each reads the previous stage's files): intake (`idea.md`) -> research (`research.md`) -> PRD (`prd.md`)
-> plan (`plan.md`, `design.md` for web UIs) -> build (`build-log.md`) -> review (`reviews/`, max 2 fix loops)
-> verify (`verify.md`) -> deliver (`report.md` + commit) -> learn (`factory-runs/lessons.md`).

Files: `commands/factory.md` (conductor), `stacks.md` (stack profiles, add-ons, method files and their headless
overrides; read at runtime), `hooks/` (guardrails), `run-headless.sh`, `eval/` (Gate 1 harness).

## Run

Interactive (asks up to 5 questions, then for PRD and release approval):

    cd D:/workspace/factory-runs
    claude --plugin-dir D:/workspace/software-factory/factory-plugin
    > /factory "a CLI to track my team leave days"      (may be listed as /factory:factory)

Headless (no questions; assumptions go to `idea.md`):

    ./run-headless.sh "a CLI to track my team leave days" 25 > run.jsonl
    ./run-headless.sh --thorough "a habit tracker web app with SQLite" 60 > run.jsonl
    ./run-headless.sh --resume D:/workspace/factory-runs/<slug> 25 > resume.jsonl

| Flag | Effect |
|---|---|
| `--auto` | No questions or approval gates; written assumptions instead (always set by `run-headless.sh`) |
| `--thorough` | Turns on the heavy extras in the tier table |
| `--resume <run dir>` | Skips stages whose artifact exists and starts at the first missing one |
| `--pr` | After the commit: branch `factory/<slug>`, push and open a PR, only if the repo has an `origin` remote |
| `--oss` | Adds open-source packaging (LICENSE, CONTRIBUTING, setup.sh, CLAUDE.md, issue templates) |

Gates (interactive only; `--auto` skips them): G1 you answer the intake questions; G2 you approve the PRD (approve,
request changes = revise and ask again, or stop); G3 you approve the release after Verify, before the commit/PR
(approve or stop). Approvals are logged as `g2: done` / `g3: done` in `run-log.md`, so `--resume` does not re-ask
them; a stopped run resumes at the gate.

Cost: `report.md` ends with a `Cost:` line. Interactive runs write `Cost: n/a (interactive; check /cost)`.
`run-headless.sh` tees the stream-json output, reads `total_cost_usd` from the final result message (node) and writes
`Cost: $X.XX (headless, total)` into the report (a resume adds a `(headless, resume)` line; if the run stopped
before Deliver, the line goes to `run-log.md`). No per-stage ledger or budget hook; `--max-budget-usd` is the cap.

## Stacks

The PRD states `Stack: <profile>`; the plan adds `UI:`, `DB:`, `ML:` lines. Profiles (details in `stacks.md`):

| Profile | Reviewer | Build-fixer | Test skill |
|---|---|---|---|
| python (default) | python-reviewer | tdd-guide (none exists) | tdd |
| typescript / node / nextjs | typescript-reviewer | build-error-resolver | tdd + e2e (Playwright) |
| go | go-reviewer | go-build-resolver | go-test |
| rust | rust-reviewer | rust-build-resolver | rust-test |
| kotlin / android / kmp | kotlin-reviewer | kotlin-build-resolver + gradle-build | kotlin-test |
| cpp | cpp-reviewer | cpp-build-resolver | cpp-test |
| flutter / dart | flutter-reviewer | dart-build-resolver | flutter-test |
| java / spring boot | java-reviewer | java-build-resolver | tdd |
| csharp / .net | csharp-reviewer | tdd-guide (none exists) | tdd |

Add-ons: `database-reviewer` when there is SQL or an ORM; `pytorch-build-resolver` for Python ML projects.
Only the python profile has been run end to end; the others are untested wiring.

## Tiers

| Stage | Default (always on) | `--thorough` adds |
|---|---|---|
| Intake | prompt-optimize | |
| Research | deep-research (2 researchers), docs-lookup if context7 is installed | 3 researchers + one gap round |
| PRD | prp-prd | |
| Plan | planner + prp-plan; architect (UI or DB apps); database-reviewer (DB); frontend-design (web UI) | code-architect |
| Build | tdd-guide + tdd/stack test skill + prp-implement + test-coverage; stack build-fixer on failure | gan-build polish loop (web UI, 3 iterations) |
| Review | stack reviewer + code-review, security-reviewer + security-review, database-reviewer (DB) | santa-loop, ponytail-review, silent-failure-hunter, type-design-analyzer (typed), performance-optimizer, pr-test-analyzer |
| Verify | general-purpose evaluator + verify + run + test-coverage; e2e-runner + e2e (web UI) | gan-evaluator, quality-gate |
| Deliver | doc-updater (update-docs, update-codemaps), prp-commit; prp-pr with `--pr`; opensource-packager with `--oss` | |
| Learn | learn + learn-eval -> `lessons.md` (read by later Plan and Build stages) | |

Review rounds 2+ rerun only the stack reviewer, security-reviewer and reviewers that still had CRITICAL/HIGH.

## Guardrails (`hooks/guard.js`, a PreToolUse hook)

Enforced: blocks `rm -r`/`Remove-Item -Recurse`/`rmdir /s` unless every target is inside `FACTORY_RUNS`
(default `D:/workspace/factory-runs`; globs, `~` and variables are refused); blocks `git push --force`/`-f`/`+ref`;
blocks shell commands and Read/Grep/Glob that touch `.env*` (except `.env.example`/`.sample`/`.template`),
credentials, `.pem`, `.ssh/`, `.aws/`, `.netrc`, `.npmrc`; blocks Write/Edit and shell redirection/`rm`/`mv`/`cp`
for report-only agents (`*-reviewer` incl. security-reviewer and database-reviewer, code-reviewer,
performance-optimizer, gan-evaluator, silent-failure-hunter, type-design-analyzer, pr-test-analyzer, planner,
architect, code-architect); blocks AskUserQuestion in headless runs (`FACTORY_AUTO=1`).
Not enforced: the evaluator's "only write `verify.md`" (instruction only), and writes done by an allowlisted
interpreter (e.g. `python -c`) inside a report-only agent. The regexes read command text; they are not a shell
parser. The hook applies to the whole session the plugin is loaded in. In headless runs the narrow `--allowedTools`
list in `run-headless.sh` is the main gate; it never uses `bypassPermissions`.

## Gate 1 eval

`./eval/run-gate.sh [budget_per_idea] [--thorough]` runs the 5 ideas in `eval/ideas.txt` one after another and
appends a pass@1 table to `eval/results.md`. Gate 1 passes at 3 of 5 `VERIFY: PASS`. About 2 hours and
$40-60 at the default tier.

## Not wired (and why)

| Skill / agent | Reason |
|---|---|
| multi-plan, multi-frontend, multi-backend | Need `~/.claude/bin/codeagent-wrapper`, `~/.claude/.ccg/prompts/` and the codex/gemini CLIs; none are installed. They also stop for user selection/approval. |
| plan | Says "WAIT for user CONFIRM"; the factory uses the same `planner` agent directly with prp-plan instead. |
| save-session, resume-session | Write to `~/.claude/session-data/` (outside the run dir, denied headless); save-session waits for confirmation and resume-session refuses to start work. `--resume` uses the stage artifacts instead. |
| instinct-status, instinct-import, instinct-export | Need `~/.claude/skills/continuous-learning-v2/scripts/instinct-cli.py`, which is not installed. Lessons go to `lessons.md`. |
| hookify (rule files) | Its `.claude/hookify.*.local.md` rules need the hookify rule engine, which is not installed; plain plugin hooks are used instead. |
| prompt-optimizer (skill) | `prompt-optimize` is a shim for this skill, which is not on disk; the shim's own rules are applied. |
| docs-lookup | Wired, but only runs when the context7 MCP is present; it is not configured on this machine, so it is skipped. |

Git runs only as `git -C <run dir> ...`: Claude Code always denies `cd <dir> && git ...` compounds. With `--pr`,
`gh pr create` is untested (no run has had a remote yet).

Partly applied: santa-loop's reviewer B falls back to a second Claude `code-reviewer` (no codex/gemini) and never
pushes; e2e-runner uses Playwright, not agent-browser; learn/learn-eval write to `lessons.md`, not
`~/.claude/skills/learned/`.

## Later (not wired into runs)

- `workflow-authoring`: rewrite the conductor as a Workflow script (deterministic stage order, the Phase 2 step).
- `loop`: re-run a stage or poll a long run on an interval.
- `schedule`: nightly Gate 1 eval as a scheduled cloud agent.

## Portability

The plugin adds only the conductor, `stacks.md`, hooks and scripts. Every agent and skill it calls lives in the
user's `~/.claude` (`agents/`, `commands/`, `.agents/skills/`, `skills/synced/` for `anthropic-skills:deep-research`)
or in installed plugins (`ponytail`, `frontend-design`). On another machine those must be installed, and
`RUNS_ROOT` in `commands/factory.md` / `FACTORY_RUNS` must point at a real folder.
