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

is_empty_repo() {
  ! git rev-parse HEAD >/dev/null 2>&1
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
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+commit'; then
    # Allow the very first commit in an empty repo — there's no branch to create yet
    if is_main_branch "$BRANCH" && ! is_empty_repo; then
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

  # ── git cherry-pick on main/master ──────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+cherry-pick'; then
    if is_main_branch "$BRANCH"; then
      emit_block "Learning moment: you're about to cherry-pick a commit directly onto '$BRANCH'.

Cherry-picking creates a new commit on '$BRANCH'. That's the same as
committing directly to '$BRANCH' — it changes the branch everyone
relies on being stable.

What to do instead:
  git checkout -b feature/your-feature-name   # create a safe branch first
  git cherry-pick <commit>                    # cherry-pick onto the branch
  git push origin feature/your-feature-name   # push and open a PR

I've paused the command. Want me to create a feature branch first?"
    fi
  fi

  # ── git revert on main/master ───────────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+revert'; then
    if is_main_branch "$BRANCH"; then
      emit_block "Learning moment: you're about to revert a commit directly on '$BRANCH'.

A revert creates a new commit that undoes a previous change. Even though
you're undoing something, it's still a commit directly to '$BRANCH'.

What to do instead:
  git checkout -b fix/revert-description      # create a branch for the revert
  git revert <commit>                         # revert on the branch
  git push origin fix/revert-description      # push and open a PR

I've paused the command. Want me to create a branch for this revert?"
    fi
  fi

  # ── git push targeting main/master ──────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+push'; then

    # ── Destructive: delete remote main ────────────────────────────────
    # git push origin --delete main / git push origin :main
    if echo "$SUBCMD" | grep -qE '(--delete[[:space:]]+(main|master)|[[:space:]]:(main|master))([[:space:]]|$)'; then
      emit_block "Learning moment: you're about to DELETE the remote '$BRANCH' branch.

This would remove '$BRANCH' from GitHub entirely. Everyone who depends
on it would lose access. This is almost never what you want.

I've paused the command. If you're trying to clean up, you probably
want to delete a feature branch instead:
  git push origin --delete feature/your-feature-name"
    fi

    # ── Dangerous: push --all / push --mirror ──────────────────────────
    if echo "$SUBCMD" | grep -qE '[[:space:]]--(all|mirror)([[:space:]]|$)'; then
      emit_block "Learning moment: you're about to push ALL branches to the remote.

This includes '$BRANCH' and every other branch. It's a bulk operation
that's rarely what you want, especially with protected branches.

Better practice:
  git push origin feature/your-feature-name   # push just your feature branch

I've paused the command. Want me to push only your feature branch?"
    fi

    TARGET=""
    IS_FORCE=false

    # Check for force push flags
    if echo "$SUBCMD" | grep -qE '[[:space:]](-f|--force|--force-with-lease)([[:space:]]|$)'; then
      IS_FORCE=true
    fi

    # Explicit target: git push origin main / git push origin master
    if echo "$SUBCMD" | grep -qE '[[:space:]](main|master)([[:space:]]|$)'; then
      TARGET=$(echo "$SUBCMD" | grep -oE '[[:space:]](main|master)([[:space:]]|$)' | head -n1 | tr -d '[:space:]')
    fi
    # Explicit refspec targeting main/master: git push origin HEAD:main
    # Also catches full refspec: git push origin HEAD:refs/heads/main
    if [ -z "$TARGET" ]; then
      if echo "$SUBCMD" | grep -qE '[[:space:]]\+?\S+:(refs/heads/)?(main|master)([[:space:]]|$)'; then
        TARGET=$(echo "$SUBCMD" | grep -oE '(main|master)([[:space:]]|$)' | head -n1 | tr -d '[:space:]')
      fi
    fi
    # git push origin HEAD when on main/master (HEAD resolves to current branch)
    if [ -z "$TARGET" ] && is_main_branch "$BRANCH"; then
      if echo "$SUBCMD" | grep -qE '[[:space:]]HEAD([[:space:]]|$)'; then
        TARGET="$BRANCH"
      fi
    fi
    # Bare push (git push / git push origin) when on main/master
    if [ -z "$TARGET" ] && is_main_branch "$BRANCH"; then
      if echo "$SUBCMD" | grep -qE '(^|[[:space:]])git[[:space:]]+push([[:space:]]+(origin|upstream))?[[:space:]]*$'; then
        TARGET="$BRANCH"
      fi
    fi

    if [ -n "$TARGET" ]; then
      if [ "$IS_FORCE" = true ]; then
        emit_block "Learning moment: you're about to FORCE PUSH to '$TARGET'.

This is one of the most dangerous git operations. Force pushing to
'$TARGET' rewrites the remote history. It can destroy other people's
commits and break everyone's local copies.

Even experienced engineers avoid this. If you need to fix something
on '$TARGET', the safe way is:
  1. Create a fix branch
  2. Push the fix branch
  3. Open a PR

I've paused the command. Want me to help you fix this safely?"
      else
        emit_block "Learning moment: you're about to push directly to '$TARGET'.

Pushing to '$TARGET' shares your work with everyone immediately.
If something is broken, it affects everyone.

Better practice:
  git push origin feature/your-feature-name
  # Then open a pull request on GitHub to review before merging into $TARGET

I've paused the push. Want me to push to a feature branch instead?"
      fi
    fi
  fi

  # ── git merge into main/master ───────────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+merge'; then
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

  # ── git pull <remote> <branch> into main (hidden merge) ─────────────────
  # "git pull origin feature/x" while on main = fetch + merge into main
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+pull'; then
    if is_main_branch "$BRANCH"; then
      # git pull with a specific branch argument (not bare "git pull")
      if echo "$SUBCMD" | grep -qE 'git[[:space:]]+pull[[:space:]]+\S+[[:space:]]+\S+'; then
        PULL_BRANCH=$(echo "$SUBCMD" | grep -oE 'git[[:space:]]+pull[[:space:]]+\S+[[:space:]]+(\S+)' | awk '{print $NF}')
        if [ -n "$PULL_BRANCH" ] && ! is_main_branch "$PULL_BRANCH"; then
          emit_block "Learning moment: you're about to pull '$PULL_BRANCH' into '$BRANCH'.

'git pull origin $PULL_BRANCH' fetches that branch and merges it directly
into '$BRANCH'. That's the same as merging without a pull request — it
skips code review.

The standard workflow is:
  1. Push your feature branch:  git push origin $PULL_BRANCH
  2. Open a pull request on GitHub
  3. Review the changes
  4. Merge the PR on GitHub

I've paused the command. Want me to push the branch and open a PR instead?"
        fi
      fi
    fi
  fi

done <<< "$SUBCMDS"

exit 0
