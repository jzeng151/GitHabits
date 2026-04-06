# GitHabits — Architecture

## Overview

GitHabits is a Claude Code hook framework that teaches git best practices to new developers at the moment of violation. It intercepts git operations via Claude Code's PreToolUse hook system and injects educational messages before allowing or blocking the action.

```
User asks Claude to "save my work"
         │
         ▼
Claude decides to run: git commit -m "..."
         │
         ▼
PreToolUse hook fires (pre_tool_use.sh)
         │
    ┌────┴──────────────────────────────┐
    │  Is this a git write operation?   │
    │  (fast-path grep — no subprocess) │
    └────┬──────────────────────────────┘
         │ YES                    NO → exit 0 (allow)
         ▼
    ┌────┴──────────────────────────────┐
    │  Parse stdin JSON via python3/jq  │
    │  Extract command string           │
    │  Split on &&, ||, ;               │
    │  Evaluate each sub-command        │
    └────┬──────────────────────────────┘
         │
    ┌────┴──────────────────────────────┐
    │  Is any sub-command targeting     │
    │  main/master or detached HEAD?    │
    └────┬──────────────────────────────┘
         │ YES                    NO → exit 0 (allow)
         ▼
    ┌────┴──────────────────────────────┐
    │  GITHABITS_ALLOW_MAIN=1 set?      │
    └────┬──────────────────────────────┘
         │ YES → exit 0 (allow)   NO ↓
         ▼
  Write tutor-voice message to stderr
  (shown in Claude Code UI immediately)
  Output JSON to stdout:
  {"decision":"block","reason":"..."}
  exit 2 (block)
         │
         ▼
Claude reads "reason" field →
elaborates on the lesson in its response
         │
         ▼
User sees: hook notification + Claude's explanation
         │
         ▼
User asks Claude to create a feature branch
         │
         ▼
Claude runs: git checkout -b feature/...
(hook fires again — now on feature branch — passes)
         │
         ▼
Claude runs: git commit, git push
CLAUDE.md rule 3: one-sentence history summary
```

---

## Components

### `hooks/pre_tool_use.sh`

The enforcement layer. Runs before every Bash tool call Claude makes.

**Inputs:**
- stdin: JSON — `{"tool_name": "Bash", "tool_input": {"command": "..."}}`

**Outputs:**
- stdout: JSON — `{"decision": "block", "reason": "..."}` (on block)
- stderr: Tutor-voice message (shown directly in Claude Code UI)
- exit 0: allow through
- exit 2: block

**Detection logic:**

```
pre_tool_use.sh
│
├── Fast path: grep for "git " in raw stdin
│   └── No match → exit 0 immediately (zero subprocess overhead)
│
├── Parse stdin JSON (python3 primary, jq fallback)
│   └── Parse failure → exit 0 (fail open, never break user's workflow)
│
├── Split command on &&, ||, ; → evaluate each sub-command
│
└── For each sub-command:
    ├── Detached HEAD check
    │   └── git branch --show-current returns empty → block (separate message)
    ├── Main/master commit check
    │   └── current branch = main/master AND git commit → block
    ├── Push-to-main check
    │   ├── "git push origin main" or "git push origin master" → block
    │   └── bare "git push" when tracking branch is main → block
    └── Merge-to-main check
        └── "git merge" when current branch is main/master → block
```

**Trigger patterns:**

| Command | Detection method | Action |
|---------|-----------------|--------|
| `git commit` on main | `git branch --show-current` | Block |
| `git push origin main` | Command string parse | Block |
| `git push origin master` | Command string parse | Block |
| bare `git push` on main | `git rev-parse --abbrev-ref @{upstream}` | Block |
| `git merge` into main | Current branch + command parse | Block |
| `git commit` in detached HEAD | `git branch --show-current` returns empty | Block (separate message) |
| `git push origin feature/x` | Command string parse | Allow |
| Any non-git command | Fast-path grep | Allow (zero overhead) |

---

### `templates/CLAUDE.md`

The explanation layer. Three rules injected into the user's CLAUDE.md (global or project-level) between `# GitHabits START` and `# GitHabits END` delimiters.

```
# GitHabits START
1. Before running any git command, explain each part in plain English before executing it.
2. Before committing, check the current branch. If main — ask the user to name a feature
   branch first. (The hook will hard-block if this soft check is missed.)
3. After every successful push, give a one-sentence summary of what the git history
   looks like now.
# GitHabits END
```

The delimiters enable clean uninstall — `setup.sh --uninstall` removes exactly this block.

---

### `setup.sh`

The installer. Idempotent. No side effects on re-run.

```
setup.sh
│
├── Check Claude Code version (minimum: JSON+exit2 fix, April 2026)
├── Install hook
│   ├── Copy hooks/pre_tool_use.sh → ~/.claude/hooks/pre_tool_use.sh (global)
│   │   or .claude/hooks/pre_tool_use.sh (--project flag)
│   └── Register in settings.json
│       ├── If hooks.PreToolUse exists → append entry (idempotent: skip if exists)
│       └── If not → create key
├── Inject CLAUDE.md rules
│   ├── If # GitHabits START already present → skip (idempotent)
│   └── Append block to ~/.claude/CLAUDE.md (global) or .claude/CLAUDE.md (--project)
└── Print: what was installed + how to uninstall

setup.sh --uninstall
│
├── Remove hook entry from settings.json (python3 JSON merge)
├── Delete hook script file
└── Remove # GitHabits START...END block from CLAUDE.md
```

**`settings.json` hook registration format:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/pre_tool_use.sh"
          }
        ]
      }
    ]
  }
}
```

Merge strategy: append if the key exists; create if not. python3 is used for JSON manipulation (available by default on macOS/Linux, no jq dependency).

---

## Data Flow: How the Hook Receives Commands

PreToolUse hooks receive the intercepted tool call as JSON on stdin:

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'add login page'"
  }
}
```

The hook reads stdin, parses with python3, and extracts `tool_input.command`. This is the command string that gets checked against the detection logic.

```sh
STDIN=$(cat)
CMD=$(echo "$STDIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['tool_input']['command'])" 2>/dev/null)
```

---

## Key Dependencies

| Dependency | Where used | Fallback |
|------------|-----------|---------|
| Claude Code PreToolUse hooks | Core enforcement layer | None — required |
| JSON+exit2 hook behavior (April 2026 fix) | Block mechanism | Older versions: install fails with version check |
| python3 | stdin JSON parsing, setup.sh JSON merge | jq (if available) |
| jq | Fallback for stdin JSON parsing | exit 0 if neither present |
| Bash 3.2+ | Hook script runtime | None — macOS default |
| git | Branch detection in hook | Hook fails open if git unavailable |

---

## Performance

The hook fires before EVERY Bash tool call. Performance is a first-class concern.

**Fast path:** The first thing the hook does is `grep -q '"git '` on the raw stdin string — before any subprocess calls, before any python3, before any git commands. Non-git bash calls (npm, ls, echo, etc.) exit in microseconds.

**Slow path (git commands only):** python3 subprocess + `git branch --show-current` + optional `git rev-parse`. Total overhead: ~50-100ms per git command. Acceptable — git commands happen ~5-10 times per session.

---

## File Structure

```
GitHabits/
├── hooks/
│   └── pre_tool_use.sh       # The hook — detection + block logic
├── templates/
│   └── CLAUDE.md             # CLAUDE.md rules template
├── test/
│   ├── hook.bats             # bats tests for pre_tool_use.sh
│   └── setup.bats            # bats tests for setup.sh
├── setup.sh                  # Installer
├── CLAUDE.md                 # Project routing rules (gstack)
├── DESIGN-DOC.md             # Design decisions and rationale
├── ARCHITECTURE.md           # This file
├── ROADMAP.md                # Feature phases
├── TODOS.md                  # Deferred work with context
└── README.md                 # Install, configuration, uninstall
```

---

## Future Architecture: Standalone CLI Path (V2)

The hook logic currently lives inline in `pre_tool_use.sh`. In V2, it will be extracted to `lib/githabits.sh` — a shared shell library that can be imported by:

1. The Claude Code PreToolUse hook (current)
2. A git-level hook (`.git/hooks/pre-commit`) for non-Claude-Code workflows
3. A standalone binary for agents other than Claude Code

```
V2 Architecture:
                    lib/githabits.sh
                    (shared detection logic)
                    /        |         \
hooks/pre_tool_use.sh   .git/hooks/    bin/githabits
(Claude Code)           pre-commit     (standalone CLI)
```

The public interface of `lib/githabits.sh`:
- `githabits_is_main_branch` — returns 0 if on main/master
- `githabits_is_write_op` — returns 0 if command is a git write operation
- `githabits_block_message` — outputs the tutor-voice message for a given violation type
- `githabits_detached_head` — returns 0 if in detached HEAD state

---

## Security Considerations

**Override mechanism:** `GITHABITS_ALLOW_MAIN=1` is documented in README only — not in the hook's block message. Claude Code agents can read block messages and potentially self-apply overrides. Keeping the override out of the block message prevents autonomous bypass.

**Hook escape hatch:** If python3 and jq are both unavailable, the hook exits 0 (allows through). This is "fail open" — the user's workflow is never broken by a missing dependency. The tradeoff is that the hook provides no protection on those systems. Acceptable for MVP.

**No network calls:** The hook makes no outbound network calls. It only reads from stdin, calls local git commands, and writes to stdout/stderr.
