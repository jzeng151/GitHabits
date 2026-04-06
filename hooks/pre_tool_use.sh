#!/usr/bin/env bash
# GitHabits — PreToolUse hook
# Intercepts git write operations and teaches branching practices.
#
# Dual output on block:
#   stderr → shown in Claude Code UI (human reads it immediately)
#   stdout → JSON {"decision":"block","reason":"..."} (Claude reads it)
#   exit 2  → blocks the tool call
#
# Allow: exit 0 with no output

set -euo pipefail

# ── Override ──────────────────────────────────────────────────────────────────
# Documented in README only — NOT in the block message.
# Claude can read block messages and self-apply overrides.
if [ "${GITHABITS_ALLOW_MAIN:-}" = "1" ]; then
  exit 0
fi

# ── Read stdin ────────────────────────────────────────────────────────────────
STDIN=$(cat)

# ── Fast path ─────────────────────────────────────────────────────────────────
# Exit immediately if this isn't a git command.
# Zero subprocess overhead for npm, ls, echo, etc.
echo "$STDIN" | grep -q '"git ' || exit 0

# ── Parse command from stdin JSON ─────────────────────────────────────────────
# stdin format: {"tool_name": "Bash", "tool_input": {"command": "..."}}
# Pass STDIN as argument (not pipe) so heredoc can provide the Python script.
CMD=""
if command -v python3 >/dev/null 2>&1; then
  CMD=$(python3 - "$STDIN" <<'PYEOF'
import sys, json
try:
    data = json.loads(sys.argv[1])
    print(data["tool_input"]["command"])
except Exception:
    pass
PYEOF
  ) || true
elif command -v jq >/dev/null 2>&1; then
  CMD=$(echo "$STDIN" | jq -r '.tool_input.command' 2>/dev/null) || true
fi

[ -z "$CMD" ] && exit 0

# ── Build and emit a block ────────────────────────────────────────────────────
# Writes tutor message to stderr (human-visible in Claude Code UI)
# and outputs JSON to stdout (Claude reads the reason field).
emit_block() {
  local msg="$1"
  echo "$msg" >&2
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$msg" <<'PYEOF'
import sys, json
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PYEOF
  else
    # Fallback: basic JSON escape
    local escaped
    escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
    printf '{"decision":"block","reason":"%s"}' "$escaped"
  fi
  exit 2
}

# ── Branch helpers ────────────────────────────────────────────────────────────
current_branch() {
  git branch --show-current 2>/dev/null || echo ""
}

is_main_branch() {
  [ "$1" = "main" ] || [ "$1" = "master" ]
}

# ── Split chained commands ────────────────────────────────────────────────────
# Handles: git checkout main && git merge feature-branch
# Splits on &&, ||, ; so each sub-command is evaluated independently.
SUBCMDS=""
if command -v python3 >/dev/null 2>&1; then
  SUBCMDS=$(python3 - "$CMD" <<'PYEOF'
import sys, re
cmd = sys.argv[1]
parts = re.split(r'&&|\|\||;', cmd)
for p in parts:
    p = p.strip()
    if p:
        print(p)
PYEOF
  ) || SUBCMDS="$CMD"
else
  SUBCMDS="$CMD"
fi

[ -z "$SUBCMDS" ] && SUBCMDS="$CMD"

# ── Evaluate each sub-command ─────────────────────────────────────────────────
BRANCH=$(current_branch)

while IFS= read -r SUBCMD; do
  [ -z "$SUBCMD" ] && continue

  # ── Detached HEAD state ──────────────────────────────────────────────────
  if [ -z "$BRANCH" ]; then
    if echo "$SUBCMD" | grep -qE '(^|[[:space:]])git[[:space:]]+(commit|merge|push)'; then
      emit_block "Learning moment: you're in 'detached HEAD' state.

This happens when you check out a specific old commit instead of a branch.
Any commits you make here aren't attached to a branch — they can be lost.

How to get back on a branch:
  git checkout main          # go back to main
  git checkout -b feature/x  # or start a new feature branch here

I've paused the command. Want me to get you back on a branch first?"
    fi
    continue
  fi

  # ── git commit on main/master ────────────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '(^|[[:space:]])git[[:space:]]+commit'; then
    if is_main_branch "$BRANCH"; then
      emit_block "Learning moment: you're about to commit directly to '$BRANCH'.

Senior engineers never do this — here's why: '$BRANCH' is the branch
your teammates (and future-you) rely on being stable. One accidental
commit can break everyone's work.

What to do instead:
  git checkout -b feature/your-feature-name   # creates a safe branch
  git add .
  git commit -m \"describe what you changed\"
  git push origin feature/your-feature-name

I've paused the command. Want me to create that branch for you?"
    fi
  fi

  # ── git push targeting main/master ──────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '(^|[[:space:]])git[[:space:]]+push'; then
    TARGET=""
    # Explicit target: git push origin main / git push origin master
    if echo "$SUBCMD" | grep -qE '[[:space:]](main|master)[[:space:]]*$'; then
      TARGET=$(echo "$SUBCMD" | grep -oE '[[:space:]](main|master)[[:space:]]*$' | tr -d '[:space:]')
    fi
    # Bare push (git push / git push origin) when on main/master
    if [ -z "$TARGET" ] && is_main_branch "$BRANCH"; then
      if echo "$SUBCMD" | grep -qE '(^|[[:space:]])git[[:space:]]+push([[:space:]]+(origin|upstream))?[[:space:]]*$'; then
        TARGET="$BRANCH"
      fi
    fi
    if [ -n "$TARGET" ]; then
      emit_block "Learning moment: you're about to push directly to '$TARGET'.

Pushing to '$TARGET' shares your work with everyone immediately.
If something is broken, it affects everyone.

Better practice:
  git push origin feature/your-feature-name
  # Then open a pull request on GitHub to review before merging into $TARGET

I've paused the push. Want me to push to a feature branch instead?"
    fi
  fi

  # ── git merge into main/master ───────────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '(^|[[:space:]])git[[:space:]]+merge'; then
    if is_main_branch "$BRANCH"; then
      emit_block "Learning moment: you're about to merge directly into '$BRANCH'.

Direct merges to '$BRANCH' skip the review step. The standard workflow is:

  1. Push your feature branch:  git push origin feature/your-feature-name
  2. Open a pull request on GitHub
  3. Review the changes
  4. Merge the PR on GitHub

I've paused the merge. Want me to push your branch and open a PR instead?"
    fi
  fi

done <<< "$SUBCMDS"

exit 0
