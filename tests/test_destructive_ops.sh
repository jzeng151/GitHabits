#!/usr/bin/env bash
# Tests for destructive operation detection in pre_tool_use.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/pre_tool_use.sh"

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

build_json() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd"
}

run_hook() {
  local cmd="$1"
  local json
  json=$(build_json "$cmd")
  STDOUT=""
  STDERR=""
  EXIT_CODE=0
  # Run in repo directory
  STDOUT=$(echo "$json" | (cd "$TMPDIR/repo" && bash "$HOOK" 2>"$TMPDIR/stderr")) || EXIT_CODE=$?
  STDERR=$(cat "$TMPDIR/stderr")
}

assert_blocked() {
  local label="$1"
  if [ "$EXIT_CODE" -eq 2 ]; then
    pass "$label — blocked (exit 2)"
  else
    fail "$label — expected exit 2, got $EXIT_CODE"
  fi
}

assert_allowed() {
  local label="$1"
  if [ "$EXIT_CODE" -eq 0 ]; then
    pass "$label — allowed (exit 0)"
  else
    fail "$label — expected exit 0, got $EXIT_CODE"
  fi
  if [ -z "$STDOUT" ]; then
    pass "$label — no stdout (clean allow)"
  else
    fail "$label — unexpected stdout: $STDOUT"
  fi
}

assert_warned() {
  local label="$1"
  if [ "$EXIT_CODE" -eq 0 ]; then
    pass "$label — exit 0 (allowed with warning)"
  else
    fail "$label — expected exit 0, got $EXIT_CODE"
  fi
  if [ -z "$STDOUT" ]; then
    pass "$label — no stdout (no block JSON)"
  else
    fail "$label — unexpected stdout: $STDOUT"
  fi
  if [ -n "$STDERR" ]; then
    pass "$label — stderr has warning"
  else
    fail "$label — stderr missing warning"
  fi
}

assert_message_contains() {
  local label="$1"
  local pattern="$2"
  if echo "$STDERR" | grep -qi "$pattern"; then
    pass "$label — message mentions '$pattern'"
  else
    fail "$label — message missing '$pattern' in: $STDERR"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
echo "=== git reset --hard (blocked) ==="
setup_repo

run_hook "git reset --hard"
assert_blocked "git reset --hard"
assert_message_contains "git reset --hard" "stash"

run_hook "git reset --hard HEAD~1"
assert_blocked "git reset --hard HEAD~1"

run_hook "git reset --hard HEAD"
assert_blocked "git reset --hard HEAD"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== git reset (safe variants allowed) ==="
setup_repo

run_hook "git reset --soft HEAD~1"
assert_allowed "git reset --soft HEAD~1"

run_hook "git reset"
assert_allowed "git reset (no flags)"

run_hook "git reset HEAD file.txt"
assert_allowed "git reset HEAD file.txt"

run_hook "git reset --mixed HEAD~1"
assert_allowed "git reset --mixed HEAD~1"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== git clean -f (blocked) ==="
setup_repo

run_hook "git clean -f"
assert_blocked "git clean -f"
assert_message_contains "git clean -f" "dry run"

run_hook "git clean -fd"
assert_blocked "git clean -fd"

run_hook "git clean -fdx"
assert_blocked "git clean -fdx"

run_hook "git clean -xf"
assert_blocked "git clean -xf"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== git clean (safe variants allowed) ==="
setup_repo

run_hook "git clean -n"
assert_allowed "git clean -n (dry run)"

run_hook "git clean -dn"
assert_allowed "git clean -dn (dry run)"

run_hook "git clean -nfd"
assert_allowed "git clean -nfd (dry run with other flags)"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== git checkout -- (blocked) ==="
setup_repo

run_hook "git checkout -- ."
assert_blocked "git checkout -- ."
assert_message_contains "git checkout -- ." "stash"

run_hook "git checkout -- file.txt"
assert_blocked "git checkout -- file.txt"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== git restore (blocked without --staged) ==="
setup_repo

run_hook "git restore ."
assert_blocked "git restore ."
assert_message_contains "git restore ." "stash"

run_hook "git restore file.txt"
assert_blocked "git restore file.txt"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== git restore --staged (allowed) ==="
setup_repo

run_hook "git restore --staged ."
assert_allowed "git restore --staged ."

run_hook "git restore --staged file.txt"
assert_allowed "git restore --staged file.txt"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Force push to feature branch (warned, not blocked) ==="
setup_repo
(cd "$TMPDIR/repo" && git checkout -b feature/test >/dev/null 2>&1)

run_hook "git push --force origin feature/test"
assert_warned "git push --force origin feature/test"
assert_message_contains "git push --force origin feature/test" "force-with-lease"

run_hook "git push --force-with-lease origin feature/test"
assert_warned "git push --force-with-lease origin feature/test"

run_hook "git push -f origin feature/test"
assert_warned "git push -f origin feature/test"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Destructive ops on feature branch (still blocked) ==="
setup_repo
(cd "$TMPDIR/repo" && git checkout -b feature/test >/dev/null 2>&1)

run_hook "git reset --hard"
assert_blocked "git reset --hard on feature branch"

run_hook "git clean -f"
assert_blocked "git clean -f on feature branch"

run_hook "git checkout -- ."
assert_blocked "git checkout -- . on feature branch"

run_hook "git restore ."
assert_blocked "git restore . on feature branch"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Chained commands with destructive ops ==="
setup_repo

run_hook "git add . && git reset --hard"
assert_blocked "git add . && git reset --hard"

run_hook "git stash && git clean -f"
assert_blocked "git stash && git clean -f"

run_hook "echo hello && git checkout -- ."
assert_blocked "echo hello && git checkout -- ."

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== GITHABITS_ALLOW_MAIN=1 bypasses all ==="
setup_repo

STDOUT=""
STDERR=""
EXIT_CODE=0
json=$(build_json "git reset --hard")
STDOUT=$(echo "$json" | (cd "$TMPDIR/repo" && GITHABITS_ALLOW_MAIN=1 bash "$HOOK" 2>"$TMPDIR/stderr")) || EXIT_CODE=$?
STDERR=$(cat "$TMPDIR/stderr")
assert_allowed "git reset --hard with GITHABITS_ALLOW_MAIN=1"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Normal git operations still allowed ==="
setup_repo

run_hook "git status"
assert_allowed "git status"

run_hook "git log"
assert_allowed "git log"

run_hook "git diff"
assert_allowed "git diff"

run_hook "git add ."
assert_allowed "git add ."

run_hook "git stash"
assert_allowed "git stash"

run_hook "git stash pop"
assert_allowed "git stash pop"

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
