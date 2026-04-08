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
echo "$STDIN" | grep -q 'git ' || exit 0

# ── Parse command from stdin JSON ─────────────────────────────────────────────
# PostToolUse stdin: {"tool_name":"Bash","tool_input":{"command":"..."},"tool_response":...}
CMD=""
TOOL_OUTPUT=""
if command -v python3 >/dev/null 2>&1; then
  eval "$(python3 - "$STDIN" <<'PYEOF'
import sys, json, shlex
try:
    data = json.loads(sys.argv[1])
    cmd = data["tool_input"]["command"]
    # tool_response can be a dict with "output" or a string
    resp = data.get("tool_response", {})
    if isinstance(resp, dict):
        output = resp.get("output", resp.get("stdout", ""))
    else:
        output = str(resp) if resp else ""
    print("CMD=%s" % shlex.quote(cmd))
    print("TOOL_OUTPUT=%s" % shlex.quote(output))
except Exception:
    pass
PYEOF
  )" || true
elif command -v jq >/dev/null 2>&1; then
  CMD=$(echo "$STDIN" | jq -r '.tool_input.command' 2>/dev/null) || true
  TOOL_OUTPUT=$(echo "$STDIN" | jq -r '.tool_response.output // .tool_response // ""' 2>/dev/null) || true
fi

[ -z "$CMD" ] && exit 0

# ── Detect failed commands ────────────────────────────────────────────────
# Don't suggest next steps if the command failed
if [ -n "$TOOL_OUTPUT" ]; then
  if echo "$TOOL_OUTPUT" | grep -qiE '(fatal:|error:|rejected|failed|denied|not found|could not)'; then
    exit 0
  fi
fi

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
      emit_hint "User just created feature branch '$BRANCH'. They are completely new to Git. Explain: They are now on a separate copy of the code called a 'branch'. Think of it like a scratch pad — anything they change here won't affect the main code until they choose to merge it. They can start writing code, and when they're ready to save a checkpoint, tell you and you'll commit their changes. Walk them through what 'committing' means: it's like saving a snapshot of their work that they can always go back to."
    fi
    ;;

  commit)
    if [ -n "$BRANCH" ] && ! is_main_branch "$BRANCH"; then
      if echo "$LAST_SUBCMD" | grep -qE '(--amend)'; then
        emit_hint "User just amended (edited) their last commit on feature branch '$BRANCH'. They are completely new to Git. Explain: Amending rewrites the last save point. If they already pushed this branch to GitHub, the old version is still there and won't match anymore. To update GitHub, they need to run: git push --force-with-lease origin $BRANCH. Explain that '--force-with-lease' tells GitHub 'replace what's there with my new version, but only if no one else changed it.' This is safer than '--force' which overwrites no matter what. Offer to run the command for them."
      else
        emit_hint "User just committed (saved a checkpoint) to feature branch '$BRANCH'. They are completely new to Git. Explain: Their changes are saved on their computer, but not on GitHub yet. The next step is to upload their branch to GitHub so others can see it. The command is: git push origin $BRANCH. Explain that 'push' means 'upload my branch to GitHub' and 'origin' is the name for their GitHub repository. After pushing, they'll need to create a 'pull request' — that's how they ask to merge their changes into the main code. Offer to push for them."
      fi
    fi
    ;;

  push)
    if [ -n "$BRANCH" ] && ! is_main_branch "$BRANCH"; then
      PR_EXISTS=false
      if command -v gh >/dev/null 2>&1; then
        PR_URL=$(gh pr view "$BRANCH" --json url --jq '.url' 2>/dev/null) || true
        if [ -n "$PR_URL" ]; then
          PR_EXISTS=true
        fi
      fi

      if [ "$PR_EXISTS" = true ]; then
        emit_hint "User just pushed updates to feature branch '$BRANCH'. A pull request already exists at $PR_URL. They are completely new to Git. Explain: Their latest changes are now uploaded and automatically appear in the pull request. If they're done making changes, walk them through how to merge: 1) Open the pull request link ($PR_URL), 2) Scroll down and look for the green 'Merge pull request' button, 3) Click 'Merge pull request', 4) Click 'Confirm merge' on the next screen. After merging, the next steps are to clean up: delete the feature branch and switch back to main."
      else
        # Try to get the repo URL for direct link
        REPO_URL=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|') || true
        emit_hint "User just pushed feature branch '$BRANCH' to GitHub. They are completely new to Git. Walk them through creating a pull request step by step: 1) Go to their repository on GitHub${REPO_URL:+ ($REPO_URL)}, 2) They should see a yellow banner at the top that says '$BRANCH had recent pushes' with a green 'Compare & pull request' button — click that button, 3) On the next page, they'll see a title and description box. The title should describe what they changed (e.g. 'Add login page'). They can leave the description blank for now, 4) Click the green 'Create pull request' button at the bottom, 5) This creates a 'pull request' which is a request to merge their changes into the main code. On a team, someone would review it first. For now they can merge it themselves, 6) On the pull request page, scroll down and click the green 'Merge pull request' button, 7) Click 'Confirm merge'. Their changes are now in the main code! Ask if they want help with any of these steps."
      fi
    fi
    ;;

  delete-branch)
    if [ -z "$BRANCH" ] || is_main_branch "$BRANCH"; then
      emit_hint "User just deleted a feature branch and is on '${BRANCH:-main}'. They are completely new to Git. Explain: They finished that feature and cleaned up the branch — good practice! Their changes are now part of the main code. Next steps: 1) Run 'git pull' to download the latest version of main, which now includes their merged changes, 2) When they're ready to start their next feature, create a new branch. Ask them: 'What are you building next?' and offer to create a branch for them with 'git checkout -b feature/<name>'. Explain that each new feature gets its own branch, like a fresh scratch pad."
    fi
    ;;

  pull)
    if [ -n "$BRANCH" ] && is_main_branch "$BRANCH"; then
      emit_hint "User just pulled (downloaded) the latest version of '$BRANCH'. They are completely new to Git. Explain: Their local code is now up to date with everything on GitHub, including any changes that were merged through pull requests. They're ready to start working on something new. Ask them: 'What would you like to build or fix next?' Then offer to create a feature branch for them. Explain: A feature branch is like a scratch pad where they can work without affecting the main code. Suggest a name based on what they describe, like 'feature/add-search' or 'fix/broken-header'."
    fi
    # TODO: merged PR detection on feature branch (see TODOS.md T3)
    ;;
esac

exit 0
