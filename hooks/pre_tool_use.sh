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

What this means: You went back in time to look at an older version of the
code. Right now, you're not on any branch — you're floating. If you make
changes here, they won't be saved to any branch and could be lost forever.

How to fix this:
  git checkout main          # go back to the main branch
  git checkout -b feature/x  # or create a new branch from this point

Think of a branch like a folder for your work. Right now your work has no
folder. I've paused the command. Want me to get you back on a branch first?"
    fi
    continue
  fi

  # ── git commit on main/master ────────────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+commit'; then
    # Allow the very first commit in an empty repo — there's no branch to create yet
    if is_main_branch "$BRANCH" && ! is_empty_repo; then
      emit_block "Learning moment: you're about to save changes directly to '$BRANCH'.

'$BRANCH' is the main version of the code that everyone shares. Think of it
like the 'official copy'. If you save changes directly here and something is
wrong, it affects everyone.

The safe way to work is to create a 'feature branch' first — it's like making
your own copy where you can work freely without affecting anyone else:

  Step 1: git checkout -b feature/your-feature-name   (create your own copy)
  Step 2: git add .                                    (select your changes)
  Step 3: git commit -m \"describe what you changed\"   (save a checkpoint)
  Step 4: git push origin feature/your-feature-name    (upload to GitHub)

After uploading, you'll create a 'pull request' on GitHub — that's how you
ask to add your changes to the official copy after review.

I've paused the command. Want me to create a feature branch for you?"
    fi
  fi

  # ── git cherry-pick on main/master ──────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+cherry-pick'; then
    if is_main_branch "$BRANCH"; then
      emit_block "Learning moment: you're about to cherry-pick a commit directly onto '$BRANCH'.

'Cherry-pick' copies a specific change and applies it as a new save. You're
about to apply it directly to '$BRANCH' — the official copy everyone shares.
Even though you're copying an existing change, this still modifies '$BRANCH'.

The safe way:
  Step 1: git checkout -b feature/your-feature-name   (create your own copy)
  Step 2: git cherry-pick <commit>                     (apply the change there)
  Step 3: git push origin feature/your-feature-name    (upload to GitHub)
  Step 4: Create a pull request on GitHub               (ask to merge it in)

I've paused the command. Want me to create a feature branch first?"
    fi
  fi

  # ── git revert on main/master ───────────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+revert'; then
    if is_main_branch "$BRANCH"; then
      emit_block "Learning moment: you're about to revert a commit directly on '$BRANCH'.

'Revert' undoes a previous change by creating a new save that cancels it out.
Even though you're undoing something, this still adds a new change directly to
'$BRANCH' — the official copy everyone shares.

The safe way:
  Step 1: git checkout -b fix/revert-description      (create your own copy)
  Step 2: git revert <commit>                          (undo the change there)
  Step 3: git push origin fix/revert-description       (upload to GitHub)
  Step 4: Create a pull request on GitHub               (ask to merge it in)

I've paused the command. Want me to create a branch for this revert?"
    fi
  fi

  # ── git push targeting main/master ──────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+push'; then

    # ── Destructive: delete remote main ────────────────────────────────
    # git push origin --delete main / git push origin :main
    if echo "$SUBCMD" | grep -qE '(--delete[[:space:]]+(main|master)|[[:space:]]:(main|master))([[:space:]]|$)'; then
      emit_block "Learning moment: you're about to DELETE the main branch from GitHub.

This would completely remove the official copy of the code from GitHub.
Everyone who depends on it would lose access. This is almost certainly
not what you want — it's one of the most destructive things you can do.

If you're trying to clean up after finishing a feature, you probably want
to delete your feature branch instead:
  git push origin --delete feature/your-feature-name

I've paused the command. Can you tell me what you're trying to do?"
    fi

    # ── Dangerous: push --all / push --mirror ──────────────────────────
    if echo "$SUBCMD" | grep -qE '[[:space:]]--(all|mirror)([[:space:]]|$)'; then
      emit_block "Learning moment: you're about to upload ALL branches to GitHub at once.

This sends every branch — including the main branch — to GitHub. It's a bulk
operation that's almost never what you want. You should only upload the specific
branch you're working on.

The safe way:
  git push origin feature/your-feature-name   (upload just your feature branch)

I've paused the command. Want me to push only your feature branch instead?"
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

This is one of the most dangerous things you can do in Git. Force pushing
to '$TARGET' replaces the version on GitHub with your version. If anyone
else made changes, those changes will be permanently deleted.

Think of it like overwriting a shared document without checking if anyone
else edited it. Even experienced engineers avoid this on '$TARGET'.

If you need to fix something, the safe way is:
  Step 1: git checkout -b fix/your-fix-name          (create your own copy)
  Step 2: Make your changes and commit them
  Step 3: git push origin fix/your-fix-name           (upload to GitHub)
  Step 4: Create a pull request on GitHub              (ask to merge it in)

I've paused the command. Want me to help you fix this safely?"
      else
        emit_block "Learning moment: you're about to upload changes directly to '$TARGET'.

'$TARGET' is the official copy of the code on GitHub. When you push
(upload) to '$TARGET', your changes go live immediately for everyone.
If something is wrong, it affects the whole team.

The safe way to share your work:
  Step 1: git push origin feature/your-feature-name   (upload your branch)
  Step 2: Go to GitHub and create a 'pull request'     (ask to merge it in)
  Step 3: Review the changes, then click 'Merge'       (add to official copy)

A pull request lets you (or your team) review changes before they go live.

I've paused the push. Want me to push to a feature branch instead?"
      fi
    fi
  fi

  # ── git merge into main/master ───────────────────────────────────────────
  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+merge'; then
    if is_main_branch "$BRANCH"; then
      emit_block "Learning moment: you're about to merge changes directly into '$BRANCH'.

'Merge' combines changes from one branch into another. You're about to add
changes directly into '$BRANCH' — the official copy — without going through
a review step. If something is wrong, it goes live immediately.

The safe way to merge:
  Step 1: git push origin feature/your-feature-name   (upload your branch)
  Step 2: Go to your repo on GitHub
  Step 3: Click 'Compare & pull request'               (create a pull request)
  Step 4: Review your changes on the pull request page
  Step 5: Click 'Merge pull request', then 'Confirm merge'

This way you can see exactly what will change before it goes into '$BRANCH'.

I've paused the merge. Want me to push your branch and create a PR instead?"
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
          emit_block "Learning moment: you're about to pull '$PULL_BRANCH' directly into '$BRANCH'.

This command downloads the '$PULL_BRANCH' branch and immediately combines it
into '$BRANCH' — the official copy. This skips the review step, so if anything
is wrong in '$PULL_BRANCH', it goes directly into the official code.

The safe way to combine branches:
  Step 1: git push origin $PULL_BRANCH                 (upload the branch)
  Step 2: Go to your repo on GitHub
  Step 3: Click 'Compare & pull request'               (create a pull request)
  Step 4: Review the changes on the pull request page
  Step 5: Click 'Merge pull request', then 'Confirm merge'

This lets you review what will change before it goes into '$BRANCH'.

I've paused the command. Want me to push the branch and create a PR instead?"
        fi
      fi
    fi
  fi

done <<< "$SUBCMDS"

exit 0
