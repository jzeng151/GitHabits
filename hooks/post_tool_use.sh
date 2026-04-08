#!/usr/bin/env bash
# GitHabits — PostToolUse hook
# Suggests the next step in the git workflow after a command completes.
#
# Output: JSON to stdout with additionalContext field (Claude rephrases).
# No stderr — Claude speaks in its own voice, not as a raw notification.
# Exit 0 always (informational, never blocking).

set -euo pipefail

# ── Override ──────────────────────────────────────────────────────────────────
if [ "${GITHABITS_QUIET:-}" = "1" ]; then
  exit 0
fi

# ── Read stdin ────────────────────────────────────────────────────────────────
STDIN=$(cat)

# ── Fast path ─────────────────────────────────────────────────────────────────
echo "$STDIN" | grep -q '"git ' || exit 0

# ── Parse command from stdin JSON ─────────────────────────────────────────────
# PostToolUse stdin: {"tool_name":"Bash","tool_input":{"command":"..."},"tool_response":...}
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

# ── Emit a workflow hint ──────────────────────────────────────────────────────
# Outputs JSON to stdout only. Claude reads additionalContext and rephrases.
emit_hint() {
  local hint="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$hint" <<'PYEOF'
import sys, json
print(json.dumps({"additionalContext": "GITHABITS: " + sys.argv[1]}))
PYEOF
  else
    local escaped
    escaped=$(printf '%s' "$hint" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
    printf '{"additionalContext":"GITHABITS: %s"}' "$escaped"
  fi
  exit 0
}

# ── Branch helpers ────────────────────────────────────────────────────────────
current_branch() {
  git branch --show-current 2>/dev/null || echo ""
}

is_main_branch() {
  [ "$1" = "main" ] || [ "$1" = "master" ]
}

# ── Split chained commands and find the last significant git operation ────────
# For "git add . && git commit -m 'fix'", the significant operation is commit.
# Priority (highest first): push > commit > checkout -b / switch -c > branch -d > pull/fetch
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

# Find the last significant git operation in the chain
LAST_OP=""
LAST_SUBCMD=""

while IFS= read -r SUBCMD; do
  [ -z "$SUBCMD" ] && continue

  if echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+push'; then
    LAST_OP="push"
    LAST_SUBCMD="$SUBCMD"
  elif echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+commit'; then
    if [ "$LAST_OP" != "push" ]; then
      LAST_OP="commit"
      LAST_SUBCMD="$SUBCMD"
    fi
  elif echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c)'; then
    if [ "$LAST_OP" != "push" ] && [ "$LAST_OP" != "commit" ]; then
      LAST_OP="new-branch"
      LAST_SUBCMD="$SUBCMD"
    fi
  elif echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+branch[[:space:]]+-[dD]'; then
    if [ "$LAST_OP" != "push" ] && [ "$LAST_OP" != "commit" ] && [ "$LAST_OP" != "new-branch" ]; then
      LAST_OP="delete-branch"
      LAST_SUBCMD="$SUBCMD"
    fi
  elif echo "$SUBCMD" | grep -qE '^[[:space:]]*git[[:space:]]+(pull|fetch)'; then
    if [ -z "$LAST_OP" ]; then
      LAST_OP="pull"
      LAST_SUBCMD="$SUBCMD"
    fi
  fi
done <<< "$SUBCMDS"

[ -z "$LAST_OP" ] && exit 0

# ── Emit hint based on operation + branch state ──────────────────────────────
BRANCH=$(current_branch)

case "$LAST_OP" in
  new-branch)
    if [ -n "$BRANCH" ] && ! is_main_branch "$BRANCH"; then
      emit_hint "User just created feature branch '$BRANCH'. They're on a safe branch now and can start making changes. Encourage them."
    fi
    ;;

  commit)
    if [ -n "$BRANCH" ] && ! is_main_branch "$BRANCH"; then
      emit_hint "User just committed to feature branch '$BRANCH'. Suggest they push to GitHub with 'git push origin $BRANCH' and then open a pull request to merge into main."
    fi
    ;;

  push)
    if [ -n "$BRANCH" ] && ! is_main_branch "$BRANCH"; then
      emit_hint "User just pushed feature branch '$BRANCH' to GitHub. Suggest they open a pull request to get their changes reviewed and merged into main. They can go to their repo on GitHub and click 'Compare & pull request', or use 'gh pr create' from the terminal."
    fi
    ;;

  delete-branch)
    if [ -z "$BRANCH" ] || is_main_branch "$BRANCH"; then
      emit_hint "User just deleted a feature branch and is on '${BRANCH:-main}'. Suggest pulling latest with 'git pull' to get any merged changes, then creating a new feature branch for their next task with 'git checkout -b feature/<name>'."
    fi
    ;;

  pull)
    if [ -n "$BRANCH" ] && is_main_branch "$BRANCH"; then
      emit_hint "User just pulled latest '$BRANCH'. They're up to date. Suggest creating a new feature branch for their next task with 'git checkout -b feature/<name>'."
    fi
    # TODO: merged PR detection on feature branch (see TODOS.md T3)
    ;;
esac

exit 0
