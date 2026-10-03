# Factory stack profiles and skill roster

The conductor reads this file at runtime. `RUN` = project dir, `PKG` = package name, `PY` = venv python
(`.venv/Scripts/python` on Windows, `.venv/bin/python` elsewhere). `CC` = `~/.claude` (the Read tool expands `~`).
Every command runs as `cd "<RUN>" && <command>`, one command per shell call. Commands not listed here (or in the
git forms in `commands/factory.md`) are denied in headless runs.

## Profiles

Fields: **detect** (words in the idea/PRD), **layout**, **setup**, **test**, **lint** (lint + typecheck/build),
**cover** (coverage), **reviewer**, **fixer** (+ its method file), **test skill** (method file the builder follows),
**verify** (how the evaluator runs the app), **typed** (type-design-analyzer runs under `--thorough`).

### python (default)
- detect: python, or no stack named. Layout: `RUN/PKG/` with `__main__.py` (`python -m PKG`), `RUN/tests/`, `pyproject.toml`; stdlib first.
- setup: `python -m venv .venv`, then `<PY> -m pip install pytest pytest-cov ruff` (+ project deps).
- test: `<PY> -m pytest -q` | lint: `<PY> -m ruff check .` | cover: `<PY> -m pytest -q --cov=<PKG> --cov-report=term`
- reviewer: `python-reviewer` | fixer: `tdd-guide` (no python build-fixer exists) with `CC/commands/build-fix.md`
- test skill: `CC/.agents/skills/tdd-workflow/SKILL.md` (the `tdd` skill) | typed: no
- verify: `<PY> -m <PKG> --help`, then each AC as a CLI command with data paths under `RUN/.verify-tmp/`.
- ML add-on: if the PRD/plan says ML (torch), runtime/training failures go to `pytorch-build-resolver`.

### typescript (also: node, nextjs, react, web app)
- Layout: `package.json`, `src/`, tests beside source (`*.test.ts`, vitest); Next.js app router for web UIs; Playwright in `RUN/e2e/`.
- setup: `npm init -y` or `npx create-next-app@latest . --ts --eslint --app --use-npm --yes`, then `npm install -D vitest @vitest/coverage-v8` (+ `@playwright/test` for web UI, then `npx playwright install chromium`).
- test: `npm test` (vitest run) | lint: `npx eslint .` and `npx tsc --noEmit` | cover: `npx vitest run --coverage`
- reviewer: `typescript-reviewer` (tell it: no CI/PR exists, review the local files) | fixer: `build-error-resolver` with `CC/commands/build-fix.md`
- test skill: `CC/.agents/skills/tdd-workflow/SKILL.md` + `CC/.agents/skills/e2e-testing/SKILL.md` (web) | typed: yes
- verify: `npm run build`; CLI: `node dist/<entry>.js --help` + ACs; web: `npx playwright test` (Playwright `webServer` starts the app).

### go
- Layout: `go.mod`, `cmd/<app>/main.go`, `internal/...`, table-driven `*_test.go`.
- setup: `go mod init <module>` | test: `go test ./...` | lint: `go vet ./...` and `go build ./...` | cover: `go test -cover ./...`
- reviewer: `go-reviewer` | fixer: `go-build-resolver` with `CC/commands/go-build.md` | test skill: `CC/commands/go-test.md` | typed: yes
- verify: `go run ./cmd/<app> --help` + ACs.

### rust
- Layout: `cargo init`, `src/main.rs` or `src/lib.rs`, unit tests in-module, integration tests in `tests/`.
- setup: `cargo init` | test: `cargo test` | lint: `cargo clippy -- -D warnings` and `cargo build` | cover: `cargo llvm-cov` (if installed, else `n/a`)
- reviewer: `rust-reviewer` | fixer: `rust-build-resolver` with `CC/commands/rust-build.md` | test skill: `CC/commands/rust-test.md` | typed: yes
- verify: `cargo run -- --help` + ACs.

### kotlin (also: android, kmp)
- Layout: Gradle wrapper, `src/main/kotlin`, `src/test/kotlin` (Kotest + MockK); Android `app/`, KMP `composeApp/`.
- setup: `gradle init --type kotlin-application --dsl kotlin` (JVM) or the template the plan names, then `./gradlew build`.
- test: `./gradlew test` | lint: `./gradlew build` (+ `./gradlew detekt` if configured) | cover: `./gradlew koverReport` (if Kover is applied)
- reviewer: `kotlin-reviewer` | fixer: `kotlin-build-resolver` with `CC/commands/kotlin-build.md`; Android/KMP also `CC/commands/gradle-build.md`
- test skill: `CC/commands/kotlin-test.md` | typed: yes
- verify: JVM `./gradlew run --args="--help"` + ACs; Android/KMP `./gradlew assembleDebug` + unit tests (no emulator).

### cpp
- Layout: `CMakeLists.txt`, `src/`, `include/`, `tests/` (GoogleTest via FetchContent).
- setup: `cmake -S . -B build` | test: `ctest --test-dir build --output-on-failure` | lint: `cmake --build build` (warnings as errors) | cover: gcov/lcov if available, else `n/a`
- reviewer: `cpp-reviewer` | fixer: `cpp-build-resolver` with `CC/commands/cpp-build.md` | test skill: `CC/commands/cpp-test.md` | typed: yes
- verify: `./build/<app> --help` + ACs.

### flutter (also: dart)
- Layout: `flutter create .` (app) or `dart create` (CLI/package); tests in `test/`.
- test: `flutter test` / `dart test` | lint: `flutter analyze` / `dart analyze` | cover: `flutter test --coverage`
- reviewer: `flutter-reviewer` | fixer: `dart-build-resolver` with `CC/commands/flutter-build.md` | test skill: `CC/commands/flutter-test.md` | typed: yes
- verify: Dart CLI `dart run bin/<app>.dart --help` + ACs; Flutter `flutter build web` + widget/integration tests (no device).

### java (also: spring boot)
- Layout: Maven (`pom.xml`, `src/main/java`, `src/test/java`, JUnit 5) unless the plan picks Gradle.
- test: `mvn -q test` | lint: `mvn -q -DskipTests verify` | cover: `mvn test jacoco:report` (if JaCoCo is configured)
- reviewer: `java-reviewer` | fixer: `java-build-resolver` with `CC/commands/build-fix.md` | test skill: `CC/.agents/skills/tdd-workflow/SKILL.md` | typed: yes
- verify: `mvn -q package` then `java -jar target/<app>.jar --help` + ACs; Spring web: integration tests with `@SpringBootTest`.

### csharp (also: .net, dotnet)
- Layout: `dotnet new sln`, `src/<App>/`, `tests/<App>.Tests/` (xUnit).
- test: `dotnet test` | lint: `dotnet build -warnaserror` and `dotnet format --verify-no-changes` | cover: `dotnet test --collect:"XPlat Code Coverage"`
- reviewer: `csharp-reviewer` | fixer: `tdd-guide` (no C# build-fixer exists) with `CC/commands/build-fix.md`
- test skill: `CC/.agents/skills/tdd-workflow/SKILL.md` | typed: yes
- verify: `dotnet run --project src/<App> -- --help` + ACs.

## Add-ons (decided from the `DB:`, `UI:` and `ML:` lines of `F/plan.md`)

| When | Agent / skill | Where |
|---|---|---|
| `DB:` is not `none` (SQL, SQLite, ORM) | `database-reviewer` (report only) | Plan (schema review) and Review round 1 |
| `UI: web` | `frontend-design:frontend-design` skill -> `F/design.md` | Plan; Build reads it |
| `UI: web` | `e2e-runner` + `e2e` skill (Playwright) | Verify |
| `ML: yes` (python) | `pytorch-build-resolver` | Build / Verify failures |

## Method files (agents Read these; general-purpose agents may load them with the Skill tool)

| Skill | File | Headless override (always applies) |
|---|---|---|
| prompt-optimize | `CC/commands/prompt-optimize.md` | Advisory only. Its target skill `prompt-optimizer` is not installed, so apply the shim's rules. |
| deep-research | Skill `anthropic-skills:deep-research` | No AskUserQuestion; files under `F/`; report to `F/research.md`; researcher cap (see factory.md). |
| prp-prd | `CC/commands/prp-prd.md` | Skip every GATE: answer its questions from `F/idea.md` + `F/research.md`; write `F/prd.md`, not `.claude/PRPs/`. |
| prp-plan | `CC/commands/prp-plan.md` | Never STOP to ask: state assumptions; return the plan text (planner is read-only). |
| tdd | `CC/.agents/skills/tdd-workflow/SKILL.md` | none |
| prp-implement | `CC/commands/prp-implement.md` | Use phases 3-4 (validate after every task) only. Plan is `F/plan.md`; no branch/stash checks, no archiving, report into `F/build-log.md`. |
| test-coverage | `CC/commands/test-coverage.md` | Builder: fill gaps to 80%. Evaluator: measure only, never add tests. |
| code-review | `CC/commands/code-review.md` | Local mode checklist only (there is no diff yet); report only. |
| security-review | `CC/.agents/skills/security-review/SKILL.md` | Report only, never edit. |
| ponytail-review | Skill `ponytail:ponytail-review` | Over-engineering findings are MEDIUM at most unless they cause a bug. |
| santa-loop | `CC/commands/santa-loop.md` | Reviewer B = Claude fallback (codex/gemini are not allowlisted). Fixes go to the fixer agent. No commits, NEVER push. |
| verify | `CC/.agents/skills/verification-loop/SKILL.md` | Report only. |
| quality-gate | `CC/commands/quality-gate.md` | No `--fix`; report only. |
| e2e | `CC/.agents/skills/e2e-testing/SKILL.md` | Playwright only (agent-browser is not allowlisted). |
| run | Skill `run` | Launch the app; stop any server you started. |
| update-docs, update-codemaps | `CC/commands/update-docs.md`, `CC/commands/update-codemaps.md` | No approval prompts; README + `docs/CODEMAPS/` only; no RUNBOOK/CONTRIBUTING. |
| prp-commit | `CC/commands/prp-commit.md` | Stage all changes; never push. |
| prp-pr | `CC/commands/prp-pr.md` | Only with `--pr` and an `origin` remote. |
| learn, learn-eval | `CC/commands/learn.md`, `CC/commands/learn-eval.md` | No confirmation; write to `<RUNS_ROOT>/lessons.md`, not `~/.claude/skills/learned/`. |
