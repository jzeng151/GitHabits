#!/usr/bin/env bash
# Tests for the PostToolUse hook (post_tool_use.sh).
#
# Creates a temporary git repo, switches branches, and feeds JSON stdin
# to the hook. Validates exit codes and stdout JSON (additionalContext hints).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/post_tool_use.sh"

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

# ── Helper: build PostToolUse JSON stdin ─────────────────────────────────────
# PostToolUse stdin: {"tool_name":"Bash","tool_input":{"command":"..."},"tool_response":{"output":"..."}}
build_json() {
  local cmd="$1"
  local output="${2:-}"
  python3 -c "
import json, sys
cmd = sys.argv[1]
output = sys.argv[2] if len(sys.argv) > 2 else ''
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': {'command': cmd},
    'tool_response': {'output': output}
}))
" "$cmd" "$output"
}

# ── Helper: run the hook ─────────────────────────────────────────────────────
# Returns: sets EXIT_CODE, STDOUT, STDERR
run_hook() {
  local cmd="$1"
  local output="${2:-}"
  local json
  json=$(build_json "$cmd" "$output")

  STDERR_FILE="$TMPDIR/stderr.tmp"
  STDOUT=$(echo "$json" | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
  STDERR=$(cat "$STDERR_FILE")
}

# ── Helper: assert hook emits a hint ─────────────────────────────────────────
assert_hint() {
  local label="$1"
  local pattern="${2:-GITHABITS}"
  if [ "$EXIT_CODE" -eq 0 ]; then
    pass "$label — exit code 0"
  else
    fail "$label — expected exit 0, got $EXIT_CODE"
  fi
  if echo "$STDOUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ctx = d.get('additionalContext', '')
assert 'GITHABITS' in ctx, f'missing GITHABITS prefix: {ctx}'
" 2>/dev/null; then
    pass "$label — stdout has GITHABITS hint"
  else
    fail "$label — stdout missing GITHABITS hint (got: $STDOUT)"
  fi
  # Check for specific pattern in the hint
  if [ "$pattern" != "GITHABITS" ]; then
    if echo "$STDOUT" | grep -qi "$pattern"; then
      pass "$label — hint contains '$pattern'"
    else
      fail "$label — hint missing '$pattern'"
    fi
  fi
}

# ── Helper: assert hook emits nothing (silent pass-through) ──────────────────
assert_silent() {
  local label="$1"
  if [ "$EXIT_CODE" -eq 0 ]; then
    pass "$label — exit code 0"
  else
    fail "$label — expected exit 0, got $EXIT_CODE"
  fi
  if [ -z "$STDOUT" ]; then
    pass "$label — no stdout (silent)"
  else
    fail "$label — unexpected stdout: $STDOUT"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Test Suite: PostToolUse Hook ==="

# ── Non-git commands → silent ────────────────────────────────────────────────
echo ""
echo "--- Fast path: non-git commands ---"

setup_repo

run_hook "ls -la" "file.txt"
assert_silent "ls -la"

run_hook "npm install" "added 100 packages"
assert_silent "npm install"

run_hook "echo hello" "hello"
assert_silent "echo hello"

# ── Git read commands → silent ───────────────────────────────────────────────
echo ""
echo "--- Git read commands (silent) ---"

run_hook "git status" "On branch main\nnothing to commit"
assert_silent "git status"

run_hook "git log --oneline" "abc123 initial commit"
assert_silent "git log"

run_hook "git diff" ""
assert_silent "git diff"

run_hook "git branch" "* main"
assert_silent "git branch"

# ── git checkout -b on feature branch → hint ─────────────────────────────────
echo ""
echo "--- git checkout -b (new branch hint) ---"

git checkout -b feature/test >/dev/null 2>&1

run_hook "git checkout -b feature/test" "Switched to a new branch 'feature/test'"
assert_hint "git checkout -b feature/test" "branch"

# ── git switch -c → hint ────────────────────────────────────────────────────
echo ""
echo "--- git switch -c (new branch hint) ---"

run_hook "git switch -c feature/login" "Switched to a new branch 'feature/login'"
assert_hint "git switch -c feature/login" "branch"

# ── git commit on feature branch → hint to push ─────────────────────────────
echo ""
echo "--- git commit on feature branch (push hint) ---"

run_hook "git commit -m 'add feature'" "[feature/test abc123] add feature"
assert_hint "git commit on feature/test" "push"

# ── git commit --amend on feature branch → hint about force push ─────────────
echo ""
echo "--- git commit --amend (force push hint) ---"

run_hook "git commit --amend -m 'updated'" "[feature/test abc123] updated"
assert_hint "git commit --amend on feature/test" "force-with-lease"

# ── git push on feature branch → hint about PR ──────────────────────────────
echo ""
echo "--- git push on feature branch (PR hint) ---"

run_hook "git push origin feature/test" "To github.com:user/repo.git\n * [new branch]      feature/test -> feature/test"
assert_hint "git push origin feature/test" "pull request"

# ── git push with -u flag → still gets hint ──────────────────────────────────
echo ""
echo "--- git push -u (PR hint) ---"

run_hook "git push -u origin feature/test" "Branch 'feature/test' set up to track 'origin/feature/test'"
assert_hint "git push -u origin feature/test" "pull request"

# ── Chained: git add && git commit → commit hint (highest priority) ──────────
echo ""
echo "--- Chained: git add && git commit (commit wins) ---"

run_hook "git add . && git commit -m 'test'" "[feature/test abc123] test"
assert_hint "git add && git commit" "push"

# ── Chained: git add && git commit && git push → push hint (highest priority)
echo ""
echo "--- Chained: git add && commit && push (push wins) ---"

run_hook "git add . && git commit -m 'test' && git push origin feature/test" "To github.com:user/repo.git"
assert_hint "git add && commit && push" "pull request"

# ── Switch to main for main-branch tests ─────────────────────────────────────
git checkout main >/dev/null 2>&1

# ── git commit on main → silent (no hint for main commits) ──────────────────
echo ""
echo "--- git commit on main (silent, no hint) ---"

run_hook "git commit -m 'test'" "[main abc123] test"
assert_silent "git commit on main"

# ── git push on main → silent ───────────────────────────────────────────────
echo ""
echo "--- git push on main (silent) ---"

run_hook "git push origin main" "To github.com:user/repo.git"
assert_silent "git push on main"

# ── git pull on main → hint to create feature branch ────────────────────────
echo ""
echo "--- git pull on main (feature branch hint) ---"

run_hook "git pull" "Already up to date."
assert_hint "git pull on main" "branch"

run_hook "git pull origin main" "Already up to date."
assert_hint "git pull origin main" "branch"

# ── git fetch on main → hint ────────────────────────────────────────────────
echo ""
echo "--- git fetch on main (hint) ---"

run_hook "git fetch" "From github.com:user/repo"
assert_hint "git fetch on main" "branch"

# ── git branch -d after returning to main → hint ────────────────────────────
echo ""
echo "--- git branch -d (cleanup hint) ---"

run_hook "git branch -d feature/test" "Deleted branch feature/test"
assert_hint "git branch -d on main" "feature"

run_hook "git branch -D feature/test" "Deleted branch feature/test"
assert_hint "git branch -D on main" "feature"

# ── Failed commands → silent (no hint) ───────────────────────────────────────
echo ""
echo "--- Failed commands (silent) ---"

run_hook "git push origin feature/test" "fatal: 'origin' does not appear to be a git repository"
assert_silent "git push with fatal error"

run_hook "git push origin feature/test" "error: failed to push some refs"
assert_silent "git push with error"

run_hook "git push origin feature/test" "! [rejected]        feature/test -> feature/test (non-fast-forward)"
assert_silent "git push rejected"

run_hook "git commit -m 'test'" "error: pathspec 'test' did not match any file(s) known to git"
assert_silent "git commit with error"

run_hook "git checkout -b feature/x" "fatal: a branch named 'feature/x' already exists"
assert_silent "git checkout -b with fatal"

run_hook "git pull origin main" "fatal: Could not read from remote repository"
assert_silent "git pull with fatal"

# ── GITHABITS_QUIET override → silent ────────────────────────────────────────
echo ""
echo "--- GITHABITS_QUIET override ---"

git checkout -b feature/quiet-test >/dev/null 2>&1

json=$(build_json "git commit -m 'test'" "[feature/quiet-test abc123] test")
STDERR_FILE="$TMPDIR/stderr.tmp"
STDOUT=$(echo "$json" | GITHABITS_QUIET=1 bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_silent "git commit with GITHABITS_QUIET=1"

git checkout main >/dev/null 2>&1

# ── Priority: push > commit > new-branch > delete > pull ────────────────────
echo ""
echo "--- Priority ordering ---"

git checkout -b feature/priority >/dev/null 2>&1

# push > commit: chain with commit then push, push hint should win
run_hook "git commit -m 'x' && git push origin feature/priority" "pushed"
assert_hint "commit && push → push wins" "pull request"

# commit > new-branch: chain with checkout -b then commit, commit hint should win
run_hook "git checkout -b feature/y && git commit -m 'x'" "[feature/y abc] x"
assert_hint "checkout -b && commit → commit wins" "push"

git checkout main >/dev/null 2>&1

# delete > pull: chain with branch -d then pull
run_hook "git branch -d feature/x && git pull" "Already up to date"
# pull is lower priority than delete-branch, so delete wins
# Actually: pull has lower priority, delete-branch wins
assert_hint "branch -d && pull → delete wins" "feature"

# ── Non-Bash tool input → no crash ──────────────────────────────────────────
echo ""
echo "--- Non-Bash tool input (graceful skip) ---"

STDERR_FILE="$TMPDIR/stderr.tmp"
STDOUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"tool_response":"file contents"}' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_silent "Read tool input"

# ── Malformed input → no crash ───────────────────────────────────────────────
echo ""
echo "--- Malformed input (graceful handling) ---"

STDOUT=$(echo 'not json' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_silent "Malformed input"

STDOUT=$(echo '' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_silent "Empty stdin"

STDOUT=$(echo '{}' | bash "$HOOK" 2>"$STDERR_FILE") && EXIT_CODE=$? || EXIT_CODE=$?
STDERR=$(cat "$STDERR_FILE")
assert_silent "Empty JSON object"

# ── Hint is valid JSON ──────────────────────────────────────────────────────
echo ""
echo "--- Hint JSON validity ---"

git checkout -b feature/json-test >/dev/null 2>&1

run_hook "git commit -m 'test with \"quotes\" and newlines'" "[feature/json-test abc] test"
if [ -n "$STDOUT" ]; then
  if echo "$STDOUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "Hint with special chars is valid JSON"
  else
    fail "Hint with special chars is invalid JSON: $STDOUT"
  fi
else
  fail "No hint produced for JSON validity test"
fi

git checkout main >/dev/null 2>&1

# ── No stderr output (Claude speaks, not the hook) ──────────────────────────
echo ""
echo "--- No stderr output ---"

git checkout -b feature/stderr-test >/dev/null 2>&1

run_hook "git commit -m 'test'" "[feature/stderr-test abc] test"
if [ -z "$STDERR" ]; then
  pass "No stderr from post hook (Claude rephrases)"
else
  fail "Unexpected stderr: $STDERR"
fi

run_hook "git push origin feature/stderr-test" "pushed"
if [ -z "$STDERR" ]; then
  pass "No stderr from push hint"
else
  fail "Unexpected stderr from push: $STDERR"
fi

git checkout main >/dev/null 2>&1

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
