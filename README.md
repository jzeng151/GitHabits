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

**With Claude Code:**
- [Claude Code](https://claude.ai/code) (PreToolUse hook support, April 2026+)
- python3 (standard on macOS and Linux)
- git

**Standalone (any git client):**
- git 2.9+ (for template directory support)
- Bash 3.2+ (macOS default)

---

## Install

### Option A — Paste into Claude Code (no terminal needed)

Copy and paste this into any Claude Code chat:

```
Please install GitHabits for me by running these steps:

1. Ask me: "Do you want GitHabits installed globally (works in every project) or just for this project?"
2. Clone the repo into a temp directory: git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
3. Based on my answer:
   - Global: bash /tmp/githabits/setup.sh
   - This project only: bash /tmp/githabits/setup.sh --project
4. Delete the installer: rm -rf /tmp/githabits

Start with step 1 — ask me the question before running anything.
```

Claude will ask you global vs. project, run the installer, and clean up after itself.

### Option B — Terminal

For global install:

```bash
git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
bash /tmp/githabits/setup.sh
rm -rf /tmp/githabits
```

For project scope install:

```bash
git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
bash /tmp/githabits/setup.sh --project
rm -rf /tmp/githabits
```

That's it. Open any project in Claude Code and start working.

### Option C — Standalone (no Claude Code)

GitHabits works with any git client: terminal, Cursor, Windsurf, aider, or any other tool that uses git.

```bash
git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
bash /tmp/githabits/setup.sh --git-hooks
rm -rf /tmp/githabits
```

This installs native git hooks via `git init.templateDir`. New repos automatically get the hooks. For existing repos, run `git init` inside them to apply.

You can also install both Claude Code hooks and git hooks together:

```bash
bash /tmp/githabits/setup.sh --git-hooks
```

If Claude Code is detected, both hook types are installed. If not, only git hooks are installed.

### Option E — MCP Server (richest agent integration)

Install an MCP server that any MCP-compatible agent can use:

```bash
git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
bash /tmp/githabits/setup.sh --mcp --git-hooks
rm -rf /tmp/githabits
```

This installs:
- **MCP server** at `~/.githabits/mcp/githabits-mcp-server` (Python3, no external dependencies)
- **Native git hooks** via `--git-hooks` for hard blocking
- Auto-registers with Claude Code, Cursor (if `.cursor/` exists), and Windsurf (if detected)

The MCP server exposes three tools:
- `validate_git_operation` — check if a git command is safe before running it
- `suggest_next_step` — get workflow guidance after a git milestone
- `explain_command` — get a plain-English explanation of a command

For agents not auto-detected (OpenCode, Codex, Goose), add to their MCP config:
- Server name: `githabits`
- Command: `python3`
- Args: `~/.githabits/mcp/githabits-mcp-server`

---

## What gets installed

### Claude Code install

- `~/.claude/hooks/pre_tool_use.sh` — blocks dangerous git operations before they run
- `~/.claude/hooks/post_tool_use.sh` — suggests the next step after each git milestone
- `~/.claude/settings.json` — registers both hooks with Claude Code
- `~/.claude/CLAUDE.md` — injects pedagogy rules into Claude's instructions

### Standalone git hooks install (`--git-hooks`)

- `~/.githabits/template/hooks/pre-commit` — blocks commits on main/master
- `~/.githabits/template/hooks/pre-push` — blocks pushes to main/master
- `~/.githabits/template/hooks/post-commit` — suggests pushing after commit
- `~/.githabits/template/hooks/post-checkout` — suggests next step after branch switch
- `~/.githabits/template/hooks/post-merge` — suggests next feature after pull
- `~/.githabits/lib/githabits.sh` — shared logic library

### MCP server install (`--mcp`)

- `~/.githabits/mcp/githabits-mcp-server` — MCP server (Python3, stdlib only)
- Agent MCP configs updated (Claude Code `settings.json`, Cursor `mcp.json`, Windsurf `mcp_config.json`)

After install with `--git-hooks`, any git client will:

1. Block commits and pushes to `main` or `master` with a clear message
2. Suggest the next step after each git milestone (commit, push, checkout, pull)

---

After install with Claude Code, Claude will:

1. Explain every git command in plain English before running it
2. Check the current branch before committing — if it's `main`, ask you to name a feature branch first
3. After every push, give a one-sentence description of what the git history looks like
4. After each git milestone, suggest the next step in the workflow

---

## What it blocks

| Command | Behavior |
|---------|----------|
| `git commit` on `main`/`master` | Blocked with tutor message |
| `git push origin main` | Blocked with tutor message |
| `git push origin HEAD` on `main` | Blocked with tutor message |
| `git push` while tracking `main` | Blocked with tutor message |
| `git merge` into `main`/`master` | Blocked with tutor message |
| `git commit` in detached HEAD state | Blocked with tutor message |
| Everything else | Allowed through |

---

## What it suggests

After each git milestone, Claude suggests the next step in plain English:

| After this... | Claude suggests... |
|---|---|
| `git checkout -b feature/x` | "You're on a safe branch. Start making changes." |
| `git commit` on a feature branch | "Push to GitHub, then open a pull request." |
| `git push origin feature/x` | "Open a pull request on GitHub." |
| `git branch -d feature/x` | "Pull latest main, start your next feature." |
| `git pull` on `main` | "Create a feature branch for your next task." |

This teaches the full branching workflow as a loop: **branch → commit → push → PR → cleanup → repeat**.

---

## Override (solo projects)

If you're working alone and want to disable branch protection for a session:

```bash
GITHABITS_ALLOW_MAIN=1 claude
```

Or set it permanently in your shell environment. This completely bypasses the hook — use it for solo projects where `main` is your working branch.

---

## Explanation scope

Control how much Claude explains when running commands:

| Scope | What gets explained |
|-------|---------------------|
| `all` | Every bash command |
| `git` | Git commands only (default) |
| `dev` | Git + npm, pip, curl, docker, chmod, mkdir, etc. |
| `none` | No automatic explanations |

You'll be asked during install.

---

## Workflow nudges

When you run a git command like `git status` or `git diff`, GitHabits checks if you have unfinished workflow steps and gently reminds you:

| State | What it detects | Nudge |
|-------|----------------|-------|
| Unpushed commits | Commits on your feature branch that haven't been pushed | "You have N unpushed commits. Push with: git push origin branch" |
| No pull request | Branch is on GitHub but has no PR | "Your branch is on GitHub but has no pull request yet." |
| PR merged | PR was merged but branch still exists locally | "Your PR was merged! Time to clean up." |

Nudges only fire when there's no milestone hint (they won't repeat what you just did). You'll be asked during install.

---

## Token usage

GitHabits adds ~750 tokens to your context window (one-time, from the CLAUDE.md rules) plus small per-event costs when hooks fire:

| Event | Input tokens | Output tokens |
|-------|-------------|---------------|
| Block (dangerous op detected) | ~160 | ~200 |
| Milestone hint (after commit/push) | ~120 | ~250 |
| Command explanation | ~66 | ~200 |
| Workflow nudge | ~40 | ~150 |

A typical active session (several commits, a push, explanations on) runs about **3,500-4,000 tokens total**. Setting `EXPLAIN_SCOPE=none` cuts per-command overhead to zero. The hook scripts themselves run in bash with zero token cost — only the JSON they return to Claude consumes tokens.

---

## Changing settings

You can change GitHabits settings anytime after install. Just ask Claude:

```
"Turn off command explanations"
"Set explanation scope to git only"
"Disable workflow nudges"
"Turn nudges back on"
```

Claude will edit the config file (`~/.claude/githabits.conf`) for you.

If you prefer the terminal, you'll need the setup script (it's deleted after install, so clone again first):

```bash
git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
bash /tmp/githabits/setup.sh --explain-scope=all # all/git/dev/none
bash /tmp/githabits/setup.sh --workflow-nudge=off # off/on
rm -rf /tmp/githabits
```

---

## Uninstall

Paste into Claude Code:

```
Please uninstall GitHabits by running these steps:

1. Ask me: "Did you install GitHabits globally or just for this project?"
2. Clone the repo: git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
3. Based on my answer:
   - Global: bash /tmp/githabits/setup.sh --uninstall
   - This project only: bash /tmp/githabits/setup.sh --project --uninstall
4. Delete the installer: rm -rf /tmp/githabits
```

Or from a terminal:

For global uninstall:

```bash
git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
bash /tmp/githabits/setup.sh --uninstall
rm -rf /tmp/githabits
```

For project scope uninstall:

```bash
git clone https://github.com/jzeng151/GitHabits.git /tmp/githabits
bash /tmp/githabits/setup.sh --project --uninstall
rm -rf /tmp/githabits
```

This removes the hook script, unregisters it from `settings.json`, and removes the GitHabits block from `CLAUDE.md`. Clean removal, nothing left behind.

---

## How it works

GitHabits uses two Claude Code hooks:

**PreToolUse** (`pre_tool_use.sh`) fires before every Bash command. When it detects a git write operation targeting `main`, it:

1. Writes a tutor-voice message to **stderr** — shown immediately in the Claude Code UI
2. Outputs `{"decision": "block", "reason": "..."}` to **stdout** — Claude reads this and elaborates
3. Exits with code `2` — blocks the command

**PostToolUse** (`post_tool_use.sh`) fires after every Bash command. When it detects a completed git milestone, it outputs a structured hint that Claude rephrases in its own voice — guiding the user to the next step in the workflow.

For the full technical design, see [ARCHITECTURE.md](ARCHITECTURE.md).
