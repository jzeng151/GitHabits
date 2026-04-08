#!/usr/bin/env bash
# Tests for the PostToolUse explanation hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/post_tool_use.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# ── Setup ────────────────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

setup_repo() {
  rm -rf "$TMPDIR/repo"
  mkdir -p "$TMPDIR/repo"
  (cd "$TMPDIR/repo" && git init -b main >/dev/null 2>&1 && \
   git config user.email "test@test.com" && git config user.name "Test" && \
   echo "init" > file.txt && git add . && git commit -m "init" >/dev/null 2>&1)
}

set_config() {
  local scope="$1"
  mkdir -p "$TMPDIR/repo/.claude"
  echo "EXPLAIN_SCOPE=$scope" > "$TMPDIR/repo/.claude/githabits.conf"
  echo "WORKFLOW_NUDGE=off" >> "$TMPDIR/repo/.claude/githabits.conf"
}

remove_config() {
  rm -f "$TMPDIR/repo/.claude/githabits.conf" 2>/dev/null || true
}

build_json() {
  local cmd="$1"
  local output="${2:-}"
  if [ -n "$output" ]; then
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"output":"%s"}}' "$cmd" "$output"
  else
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"output":""}}' "$cmd"
  fi
}

run_hook() {
  local cmd="$1"
  local output="${2:-}"
  local json
  json=$(build_json "$cmd" "$output")
  STDOUT=""
  STDERR=""
  EXIT_CODE=0
  # Override HOME to prevent reading real ~/.claude/githabits.conf
  STDOUT=$(echo "$json" | (cd "$TMPDIR/repo" && HOME="$TMPDIR/fakehome" bash "$HOOK" 2>"$TMPDIR/stderr")) || EXIT_CODE=$?
  STDERR=$(cat "$TMPDIR/stderr")
}

assert_has_explain() {
  local label="$1"
  if echo "$STDOUT" | grep -q "GITHABITS_EXPLAIN"; then
    pass "$label — has GITHABITS_EXPLAIN"
  else
    fail "$label — missing GITHABITS_EXPLAIN in stdout: '$STDOUT'"
  fi
}

assert_no_explain() {
  local label="$1"
  if echo "$STDOUT" | grep -q "GITHABITS_EXPLAIN"; then
    fail "$label — unexpected GITHABITS_EXPLAIN in stdout"
  else
    pass "$label — no GITHABITS_EXPLAIN (correct)"
  fi
}

assert_silent() {
  local label="$1"
  if [ -z "$STDOUT" ]; then
    pass "$label — silent (no stdout)"
  else
    fail "$label — unexpected stdout: '$STDOUT'"
  fi
}

assert_valid_json() {
  local label="$1"
  if [ -z "$STDOUT" ]; then
    fail "$label — no output to validate as JSON"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    if echo "$STDOUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
      pass "$label — valid JSON"
    else
      fail "$label — invalid JSON: $STDOUT"
    fi
  else
    pass "$label — skipped JSON validation (no python3)"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
echo "=== EXPLAIN_SCOPE=all ==="
setup_repo
set_config "all"

run_hook "ls -la"
assert_has_explain "ls -la with scope=all"
assert_valid_json "ls -la JSON"

run_hook "npm install"
assert_has_explain "npm install with scope=all"

run_hook "git status"
assert_has_explain "git status with scope=all"

run_hook "curl https://example.com"
assert_has_explain "curl with scope=all"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== EXPLAIN_SCOPE=git ==="
setup_repo
set_config "git"

run_hook "git status"
assert_has_explain "git status with scope=git"

run_hook "ls -la"
assert_silent "ls -la with scope=git"

run_hook "npm install"
assert_silent "npm install with scope=git"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== EXPLAIN_SCOPE=dev ==="
setup_repo
set_config "dev"

run_hook "git status"
assert_has_explain "git status with scope=dev"

run_hook "npm install express"
assert_has_explain "npm install with scope=dev"

run_hook "pip install flask"
assert_has_explain "pip install with scope=dev"

run_hook "docker ps"
assert_has_explain "docker ps with scope=dev"

run_hook "cargo build"
assert_has_explain "cargo build with scope=dev"

run_hook "ls -la"
assert_silent "ls -la with scope=dev"

run_hook "echo hello"
assert_silent "echo hello with scope=dev"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== EXPLAIN_SCOPE=none ==="
setup_repo
set_config "none"

run_hook "git status"
assert_silent "git status with scope=none"

run_hook "ls -la"
assert_silent "ls -la with scope=none"

run_hook "npm install"
assert_silent "npm install with scope=none"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Missing config (default=git) ==="
setup_repo
remove_config

run_hook "git status"
assert_has_explain "git status with no config (default git)"

run_hook "ls -la"
assert_silent "ls -la with no config (default git)"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Combined explanation + milestone hint ==="
setup_repo
set_config "git"
(cd "$TMPDIR/repo" && git checkout -b feature/test >/dev/null 2>&1 && \
 echo "change" >> file.txt && git add . && git commit -m "test change" >/dev/null 2>&1)

# git commit on feature branch → should have both explain and milestone hint
run_hook "git commit -m 'another change'" "[feature/test abc1234] another change"
assert_has_explain "git commit explanation"
# Should also have the milestone hint about pushing
if echo "$STDOUT" | grep -q "push"; then
  pass "git commit — also has push milestone hint"
else
  fail "git commit — missing push milestone hint"
fi
assert_valid_json "combined explain + milestone JSON"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Explanation alone (no milestone, no nudge) ==="
setup_repo
set_config "git"
# Stay on main — git status won't trigger milestone or nudge (nudge off, main branch)
run_hook "git status" "On branch main"
assert_has_explain "git status on main — explain only"
# Should NOT have milestone hint text
if echo "$STDOUT" | grep -q "feature branch"; then
  fail "git status on main — should not have milestone hint"
else
  pass "git status on main — no milestone hint (explain only)"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Explanation with nudge ==="
setup_repo
mkdir -p "$TMPDIR/repo/.claude"
echo "EXPLAIN_SCOPE=git" > "$TMPDIR/repo/.claude/githabits.conf"
echo "WORKFLOW_NUDGE=on" >> "$TMPDIR/repo/.claude/githabits.conf"
(cd "$TMPDIR/repo" && git checkout -b feature/test >/dev/null 2>&1 && \
 echo "change" >> file.txt && git add . && git commit -m "test change" >/dev/null 2>&1)

# git status on feature branch with unpushed commits → explain + nudge
run_hook "git status" "On branch feature/test"
assert_has_explain "git status with nudge — has explanation"
if echo "$STDOUT" | grep -qi "unpushed\|workflow\|reminder"; then
  pass "git status with nudge — has nudge text"
else
  fail "git status with nudge — missing nudge text"
fi
assert_valid_json "explain + nudge JSON"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Failed command — no explanation ==="
setup_repo
set_config "git"

run_hook "git push origin feature/nonexistent" "fatal: could not read from remote repository"
assert_silent "failed git push — silent (no explain on failure)"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== GITHABITS_QUIET=1 — no output ==="
setup_repo
set_config "all"

json=$(build_json "git status" "On branch main")
STDOUT=$(echo "$json" | (cd "$TMPDIR/repo" && GITHABITS_QUIET=1 bash "$HOOK" 2>/dev/null)) || true
if [ -z "$STDOUT" ]; then
  pass "GITHABITS_QUIET=1 — silent"
else
  fail "GITHABITS_QUIET=1 — unexpected output: $STDOUT"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Explanation includes command text ==="
setup_repo
set_config "all"

run_hook "git log --oneline -5"
if echo "$STDOUT" | grep -q "git log --oneline -5"; then
  pass "explanation includes the actual command"
else
  fail "explanation missing command text"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
  exit 1
fi
