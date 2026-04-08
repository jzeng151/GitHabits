#!/usr/bin/env bash
# Tests for the PreToolUse hook (pre_tool_use.sh).
#
# Creates a temporary git repo, switches branches, and feeds JSON stdin
# to the hook. Validates exit codes, stdout JSON, and stderr messages.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/pre_tool_use.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# ── Setup: create a git repo with an initial commit ──────────────────────────
setup_repo() {
  rm -rf "$TMPDIR/repo"
  mkdir -p "$TMPDIR/repo"
  cd "$TMPDIR/repo"
  git init -b main >/dev/null 2>&1
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > file.txt
  git add file.txt
  git commit -m "initial commit" >/dev/null 2>&1
}

# ── Helper: run the hook with a given command string ─────────────────────────
# Returns: sets EXIT_CODE, STDOUT, STDERR
run_hook() {
  local cmd="$1"
  local json
  json=$(python3 -c "import json; print(json.dumps({'tool_name':'Bash','tool_input':{'command':cmd}}))" "cmd=$cmd" 2>/dev/null || true)
  # Build JSON properly
  json=$(python3 -c "
import json, sys
print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))
" "$cmd")

  STDERR_FILE="$TMPDIR/stderr.tmp"
  STDOUT=$(echo "$json" | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
  STDERR=$(cat "$STDERR_FILE")
}

# ── Helper: assert hook blocks (exit 2, JSON with decision:block) ────────────
assert_blocked() {
  local label="$1"
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "$label — exit code 2"
  else
    fail "$label — expected exit 2, got $EXIT_CODE"
  fi
  if echo "$STDOUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['decision']=='block'" 2>/dev/null; then
    pass "$label — stdout has decision:block"
  else
    fail "$label — stdout missing decision:block (got: $STDOUT)"
  fi
  if [ -n "$STDERR" ]; then
    pass "$label — stderr has message"
  else
    fail "$label — stderr is empty"
  fi
}

# ── Helper: assert hook allows (exit 0, no stdout) ──────────────────────────
assert_allowed() {
  local label="$1"
  if [ "$EXIT_CODE" -eq 0 ]; then
    pass "$label — exit code 0"
  else
    fail "$label — expected exit 0, got $EXIT_CODE"
  fi
  if [ -z "$STDOUT" ]; then
    pass "$label — no stdout (clean allow)"
  else
    fail "$label — unexpected stdout: $STDOUT"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Test Suite: PreToolUse Hook ==="

# ── Non-git commands pass through ────────────────────────────────────────────
echo ""
echo "--- Fast path: non-git commands ---"

setup_repo

run_hook "ls -la"
assert_allowed "ls -la"

run_hook "npm install"
assert_allowed "npm install"

run_hook "echo hello world"
assert_allowed "echo hello world"

run_hook "python3 script.py"
assert_allowed "python3 script.py"

# ── git read commands pass through ───────────────────────────────────────────
echo ""
echo "--- Git read commands (allowed) ---"

run_hook "git status"
assert_allowed "git status"

run_hook "git log --oneline"
assert_allowed "git log --oneline"

run_hook "git diff"
assert_allowed "git diff"

run_hook "git branch"
assert_allowed "git branch"

run_hook "git branch --show-current"
assert_allowed "git branch --show-current"

run_hook "git remote -v"
assert_allowed "git remote -v"

run_hook "git stash list"
assert_allowed "git stash list"

# ── git commit on main → blocked ────────────────────────────────────────────
echo ""
echo "--- git commit on main (blocked) ---"

run_hook "git commit -m 'test'"
assert_blocked "git commit -m 'test' on main"

if echo "$STDERR" | grep -qi "learning moment"; then
  pass "Block message starts with 'Learning moment'"
else
  fail "Block message missing 'Learning moment'"
fi

if echo "$STDERR" | grep -qi "feature branch"; then
  pass "Block message suggests feature branch"
else
  fail "Block message missing feature branch suggestion"
fi

# ── git commit with git add chain on main → blocked ─────────────────────────
echo ""
echo "--- git add && git commit on main (blocked) ---"

run_hook "git add . && git commit -m 'test'"
assert_blocked "git add && git commit on main"

# ── git commit on feature branch → allowed ───────────────────────────────────
echo ""
echo "--- git commit on feature branch (allowed) ---"

git checkout -b feature/test >/dev/null 2>&1

run_hook "git commit -m 'test'"
assert_allowed "git commit on feature/test"

run_hook "git add . && git commit -m 'test'"
assert_allowed "git add && git commit on feature/test"

# ── git push on feature branch → allowed ─────────────────────────────────────
echo ""
echo "--- git push on feature branch (allowed) ---"

run_hook "git push origin feature/test"
assert_allowed "git push origin feature/test"

run_hook "git push -u origin feature/test"
assert_allowed "git push -u origin feature/test"

run_hook "git push"
assert_allowed "bare git push on feature branch"

# ── git merge on feature branch → allowed ────────────────────────────────────
echo ""
echo "--- git merge on feature branch (allowed) ---"

run_hook "git merge main"
assert_allowed "git merge main into feature branch"

# ── Switch back to main for blocking tests ───────────────────────────────────
git checkout main >/dev/null 2>&1

# ── git push to main (various forms) → blocked ──────────────────────────────
echo ""
echo "--- git push to main (blocked) ---"

run_hook "git push origin main"
assert_blocked "git push origin main"

run_hook "git push origin master"
assert_blocked "git push origin master"

run_hook "git push origin HEAD"
assert_blocked "git push origin HEAD on main"

run_hook "git push"
assert_blocked "bare git push on main"

run_hook "git push origin"
assert_blocked "git push origin on main"

# ── git push with refspec targeting main → blocked ───────────────────────────
echo ""
echo "--- git push refspec to main (blocked) ---"

run_hook "git push origin HEAD:main"
assert_blocked "git push origin HEAD:main"

run_hook "git push origin HEAD:refs/heads/main"
assert_blocked "git push origin HEAD:refs/heads/main"

run_hook "git push origin feature/test:main"
assert_blocked "git push origin feature/test:main"

# ── Force push to main → blocked with force-specific message ────────────────
echo ""
echo "--- Force push to main (blocked) ---"

run_hook "git push --force origin main"
assert_blocked "git push --force origin main"

if echo "$STDERR" | grep -qi "force push"; then
  pass "Force push message mentions 'force push'"
else
  fail "Force push message missing 'force push' mention"
fi

run_hook "git push -f origin main"
assert_blocked "git push -f origin main"

run_hook "git push --force-with-lease origin main"
assert_blocked "git push --force-with-lease origin main"

# ── git push --delete main → blocked ────────────────────────────────────────
echo ""
echo "--- git push --delete main (blocked) ---"

run_hook "git push origin --delete main"
assert_blocked "git push origin --delete main"

if echo "$STDERR" | grep -qi "delete"; then
  pass "Delete message mentions 'delete'"
else
  fail "Delete message missing 'delete'"
fi

run_hook "git push origin :main"
assert_blocked "git push origin :main"

# ── git push --all / --mirror → blocked ──────────────────────────────────────
echo ""
echo "--- git push --all / --mirror (blocked) ---"

run_hook "git push --all"
assert_blocked "git push --all"

run_hook "git push --mirror"
assert_blocked "git push --mirror"

# ── git merge into main → blocked ───────────────────────────────────────────
echo ""
echo "--- git merge into main (blocked) ---"

run_hook "git merge feature/test"
assert_blocked "git merge feature/test into main"

if echo "$STDERR" | grep -qi "merge"; then
  pass "Merge message mentions 'merge'"
else
  fail "Merge message missing 'merge'"
fi

# ── git cherry-pick on main → blocked ───────────────────────────────────────
echo ""
echo "--- git cherry-pick on main (blocked) ---"

run_hook "git cherry-pick abc123"
assert_blocked "git cherry-pick on main"

if echo "$STDERR" | grep -qi "cherry-pick"; then
  pass "Cherry-pick message mentions 'cherry-pick'"
else
  fail "Cherry-pick message missing 'cherry-pick'"
fi

# ── git revert on main → blocked ────────────────────────────────────────────
echo ""
echo "--- git revert on main (blocked) ---"

run_hook "git revert abc123"
assert_blocked "git revert on main"

if echo "$STDERR" | grep -qi "revert"; then
  pass "Revert message mentions 'revert'"
else
  fail "Revert message missing 'revert'"
fi

# ── git pull <remote> <feature-branch> into main → blocked ──────────────────
echo ""
echo "--- git pull feature into main (blocked) ---"

run_hook "git pull origin feature/login"
assert_blocked "git pull origin feature/login into main"

if echo "$STDERR" | grep -qi "pull"; then
  pass "Pull-feature message mentions 'pull'"
else
  fail "Pull-feature message missing 'pull'"
fi

# ── git pull (bare) on main → allowed ───────────────────────────────────────
echo ""
echo "--- git pull (bare) on main (allowed) ---"

run_hook "git pull"
assert_allowed "bare git pull on main"

run_hook "git pull origin main"
assert_allowed "git pull origin main (updating main from remote)"

# ── Detached HEAD → blocked for write ops ────────────────────────────────────
echo ""
echo "--- Detached HEAD (blocked) ---"

COMMIT_HASH=$(git rev-parse HEAD)
git checkout "$COMMIT_HASH" >/dev/null 2>&1 || true

run_hook "git commit -m 'detached'"
assert_blocked "git commit in detached HEAD"

if echo "$STDERR" | grep -qi "detached"; then
  pass "Detached HEAD message mentions 'detached'"
else
  fail "Detached HEAD message missing 'detached'"
fi

run_hook "git merge feature/test"
assert_blocked "git merge in detached HEAD"

run_hook "git push origin HEAD"
assert_blocked "git push in detached HEAD"

# ── Detached HEAD → allowed for read ops ─────────────────────────────────────
echo ""
echo "--- Detached HEAD read ops (allowed) ---"

run_hook "git status"
assert_allowed "git status in detached HEAD"

run_hook "git log"
assert_allowed "git log in detached HEAD"

# Go back to main
git checkout main >/dev/null 2>&1

# ── Empty repo: first commit on main → allowed ──────────────────────────────
echo ""
echo "--- Empty repo: first commit (allowed) ---"

rm -rf "$TMPDIR/empty-repo"
mkdir -p "$TMPDIR/empty-repo"
cd "$TMPDIR/empty-repo"
git init -b main >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"

run_hook "git commit -m 'initial'"
assert_allowed "first commit in empty repo"

# ── Chained commands: only git write ops are checked ─────────────────────────
echo ""
echo "--- Chained commands ---"

cd "$TMPDIR/repo"

run_hook "echo hello && git commit -m 'test'"
assert_blocked "echo && git commit on main"

run_hook "git status && git log"
assert_allowed "git status && git log (both reads)"

run_hook "ls -la ; git push origin main"
assert_blocked "ls ; git push origin main"

run_hook "git checkout -b feature/x && git commit -m 'test'"
# checkout -b is not blocked, but commit on main... wait, after checkout -b
# the hook checks current_branch() at runtime, which is still main because
# the hook hasn't actually run the checkout. So the commit check sees main.
# This is expected behavior — the hook evaluates against current state.
assert_blocked "checkout -b && commit (branch not changed yet)"

# ── GITHABITS_ALLOW_MAIN override ───────────────────────────────────────────
echo ""
echo "--- GITHABITS_ALLOW_MAIN override ---"

json=$(python3 -c "
import json, sys
print(json.dumps({'tool_name':'Bash','tool_input':{'command':'git commit -m test'}}))
")

STDERR_FILE="$TMPDIR/stderr.tmp"
STDOUT=$(echo "$json" | GITHABITS_ALLOW_MAIN=1 bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")

assert_allowed "git commit on main with GITHABITS_ALLOW_MAIN=1"

# ── False positive: commit message containing "git push" ─────────────────────
echo ""
echo "--- False positive prevention ---"

run_hook "git commit -m 'fix: update git push origin main docs'"
assert_blocked "git commit on main (blocked for being on main, not for message content)"

# But on a feature branch, commit messages with git keywords should pass
git checkout -b feature/false-positive-test >/dev/null 2>&1

run_hook "git commit -m 'docs: update git push origin main instructions'"
assert_allowed "commit with 'git push' in message on feature branch"

run_hook "git commit -m 'fix git merge conflict resolution'"
assert_allowed "commit with 'git merge' in message on feature branch"

git checkout main >/dev/null 2>&1

# ── git push --delete feature branch → allowed ──────────────────────────────
echo ""
echo "--- git push --delete feature branch (allowed) ---"

run_hook "git push origin --delete feature/test"
assert_allowed "git push origin --delete feature/test"

# ── master branch (not just main) → blocked ─────────────────────────────────
echo ""
echo "--- master branch detection ---"

cd "$TMPDIR"
rm -rf "$TMPDIR/master-repo"
mkdir -p "$TMPDIR/master-repo"
cd "$TMPDIR/master-repo"
git init -b master >/dev/null 2>&1
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > file.txt
git add file.txt
git commit -m "initial commit" >/dev/null 2>&1

run_hook "git commit -m 'test'"
assert_blocked "git commit on master"

run_hook "git push origin master"
assert_blocked "git push origin master (master branch)"

run_hook "git merge feature/x"
assert_blocked "git merge into master"

# ── Stdin format: non-Bash tool → no crash ───────────────────────────────────
echo ""
echo "--- Non-Bash tool input (graceful skip) ---"

STDERR_FILE="$TMPDIR/stderr.tmp"
STDOUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_allowed "Read tool input (not Bash)"

STDOUT=$(echo '{"tool_name":"Write","tool_input":{"content":"git push origin main"}}' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_allowed "Write tool with git keywords in content"

# ── Malformed JSON → no crash ────────────────────────────────────────────────
echo ""
echo "--- Malformed input (graceful handling) ---"

STDOUT=$(echo 'not json at all' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_allowed "Malformed input (not JSON)"

STDOUT=$(echo '' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_allowed "Empty stdin"

STDOUT=$(echo '{}' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_allowed "Empty JSON object"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
