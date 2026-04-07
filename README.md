# GitHabits

A Claude Code hook that teaches new developers git best practices at the moment of violation.

Instead of a cryptic block, you get:

```
Learning moment: you're about to commit directly to 'main'.

Senior engineers never do this — here's why: 'main' is the branch
your teammates (and future-you) rely on being stable. One accidental
commit can break everyone's work.

What to do instead:
  git checkout -b feature/your-feature-name
  git add .
  git commit -m "describe what you changed"
  git push origin feature/your-feature-name

I've paused the command. Want me to create that branch for you?
```

Claude explains what it's doing in plain English before every git command, blocks direct pushes to `main` or `master`, and guides you to create a feature branch instead.

---

## Requirements

- [Claude Code](https://claude.ai/code) (PreToolUse hook support, April 2026+)
- python3 (standard on macOS and Linux)
- git

---

## Install

**Global install** (applies to every project):

```bash
git clone https://github.com/jzeng151/GitHabits.git
cd GitHabits
./setup.sh
```

**Per-project install** (this project only):

```bash
./setup.sh --project
```

That's it. Open any project in Claude Code and start working.

---

## What gets installed

- `~/.claude/hooks/pre_tool_use.sh` — intercepts git commands before they run
- `~/.claude/settings.json` — registers the hook with Claude Code
- `~/.claude/CLAUDE.md` — injects three pedagogy rules into Claude's instructions

The three rules Claude follows after install:

1. Explain every git command in plain English before running it
2. Check the current branch before committing — if it's `main`, ask you to name a feature branch first
3. After every push, give a one-sentence description of what the git history looks like now

---

## What it blocks

| Command | Behavior |
|---------|----------|
| `git commit` on `main`/`master` | Blocked with tutor message |
| `git push origin main` | Blocked with tutor message |
| `git push` while tracking `main` | Blocked with tutor message |
| `git merge` into `main`/`master` | Blocked with tutor message |
| `git commit` in detached HEAD state | Blocked with tutor message |
| Everything else | Allowed through |

---

## Override (solo projects)

If you're working alone and want to disable branch protection for a session:

```bash
GITHABITS_ALLOW_MAIN=1 claude
```

Or set it permanently in your shell environment. This completely bypasses the hook — use it for solo projects where `main` is your working branch.

---

## Uninstall

```bash
./setup.sh --uninstall          # global uninstall
./setup.sh --project --uninstall  # project-only uninstall
```

This removes the hook script, unregisters it from `settings.json`, and removes the GitHabits block from `CLAUDE.md`. Clean removal, nothing left behind.

---

## How it works

GitHabits uses Claude Code's [PreToolUse hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) to intercept every Bash tool call before it executes. When it detects a git write operation targeting `main`, it:

1. Writes a tutor-voice message to **stderr** — shown immediately in the Claude Code UI
2. Outputs `{"decision": "block", "reason": "..."}` to **stdout** — Claude reads this and elaborates in its response
3. Exits with code `2` — blocks the command

You get two teaching moments: the hook notification in the UI, and Claude's response.

For the full technical design, see [ARCHITECTURE.md](ARCHITECTURE.md).
