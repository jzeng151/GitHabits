# GitHabits Roadmap

## MVP

**Goal:** A new developer using Claude Code gets blocked and taught when they try to commit to main. Install takes one command.

### Features

- [ ] `pre_tool_use.sh` — PreToolUse hook that intercepts git write operations on main branch
  - Detects `git commit` on main or master
  - Detects `git push origin main` / `git push origin master` / bare `git push` when on main
  - Detects `git merge` into main (without PR)
  - Detects `git commit` in detached HEAD state with separate message
  - Splits chained commands (`&&`, `||`, `;`) and evaluates each sub-command independently
  - Dual output: tutor-voice message to stderr (shown in Claude Code UI) + JSON block to stdout
  - Fast-path grep before any subprocess calls (no overhead on non-git commands)
  - Override via `GITHABITS_ALLOW_MAIN=1` env var (documented in README only)

- [ ] `CLAUDE.md` template — Three injected rules for Claude's behavior
  - Explain every git command in plain English before executing it
  - Check current branch before committing; ask user to name a feature branch if on main
  - One-sentence git history summary after every successful push
  - Wrapped in `# GitHabits START` / `# GitHabits END` delimiters for clean uninstall

- [ ] `setup.sh` — One-command installation script
  - Global install to `~/.claude/` by default; `--project` flag for per-project install
  - Idempotent: re-running never creates duplicate hook entries or CLAUDE.md blocks
  - Merges hook entry into `settings.json` using python3 (no jq dependency)
  - `--uninstall` flag removes all traces cleanly
  - Claude Code version check (minimum version with JSON+exit2 fix)

- [ ] `README.md` — Setup, configuration, and uninstall documentation
  - Install command (`curl | bash`)
  - `GITHABITS_ALLOW_MAIN=1` override documentation (for solo repos)
  - Uninstall instructions

---

## V2 — Roadmap-Aware Board Assistant

**Goal:** GitHabits helps the user define a feature roadmap at project start and detects when features are done.

### Features

- [ ] Roadmap creation — Claude helps user define features at project start, stored in `.claude/githabits/roadmap.md`
- [ ] Roadmap session context — Claude references open features at the start of each session
- [ ] Feature completion detection — Claude detects when current conversation has completed a roadmap item (based on context + code changes)
- [ ] Commit prompt — When a feature is done: "Looks like you finished '[feature name]' — want me to commit, push, and open a PR?"
- [ ] Roadmap update — Marks roadmap item complete after PR is created
- [ ] PostToolUse hook (optional) — Detect "significant file change" events to assist completion detection
- [ ] `/githabits done` command — Manual trigger to mark a feature complete

---

## V2 — Additional Features

**Goal:** Better coverage, smarter detection, stronger pedagogy.

### Features

- [ ] `git reset --hard` detection — Tutor-voice intervention for destructive operations
- [ ] `git push --force` detection — Educational block for force-push attempts
- [ ] PostToolUse explanation hook — Inject bash explanations via hook as fallback for long-context CLAUDE.md drift
- [ ] Detached HEAD guidance improvements — Richer message with step-by-step recovery
- [ ] `lib/githabits.sh` shared library — Extract hook logic for portability to standalone CLI

---

## V3 — Standalone CLI + Git Replay

**Goal:** Works beyond Claude Code. Teach through history.

### Features

- [ ] Standalone CLI / git hooks — Works with any agent, not just Claude Code
- [ ] Git replay mode — Post-feature post-mortem: "Here's what your git history looked like vs. what a senior engineer would have done"
- [ ] Color-coded bash explanations — When terminal rendering support is confirmed feasible
- [ ] `npx githabits init` / Homebrew — Broader discoverability and installation
- [ ] GitHub Actions CI — `shellcheck` linting, `bats` tests, auto-release on tag

---

## Known Constraints

- MVP requires Claude Code with the JSON+exit2 hook fix (April 2026+)
- MVP requires Bash 3.2+ (macOS compatible)
- MVP requires python3 (available by default on macOS/Linux) or jq
- No Node, no bun, no external runtimes for MVP
- Color-coded explanations deferred until Claude Code terminal rendering is confirmed feasible
