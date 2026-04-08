#!/usr/bin/env bash
# Tests for lib/githabits.sh — shared library functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/githabits.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

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

# ── Test: parse_command ──────────────────────────────────────────────────────
echo "=== parse_command ==="

# Source fresh for each test group (reset _GITHABITS_LIB_LOADED)
(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  CMD=""
  JSON='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  if parse_command "$JSON"; then
    if [ "$CMD" = "git status" ]; then
      echo "  ✓ extracts command from valid JSON"
    else
      echo "  ✗ expected 'git status', got '$CMD'"
    fi
  else
    echo "  ✗ parse_command returned failure on valid JSON"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  CMD=""
  JSON='not valid json at all'
  if parse_command "$JSON"; then
    echo "  ✗ should have returned failure on invalid JSON"
  else
    echo "  ✓ returns failure on invalid JSON"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  CMD=""
  JSON='{}'
  if parse_command "$JSON"; then
    echo "  ✗ should have returned failure on empty object"
  else
    echo "  ✓ returns failure on empty object"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  CMD=""
  JSON='{"tool_name":"Bash","tool_input":{"command":"echo hello && git commit -m test"}}'
  if parse_command "$JSON"; then
    if [ "$CMD" = "echo hello && git commit -m test" ]; then
      echo "  ✓ extracts chained command string intact"
    else
      echo "  ✗ expected chained command, got '$CMD'"
    fi
  else
    echo "  ✗ parse_command returned failure on chained command"
  fi
)

# ── Test: parse_command_and_output ───────────────────────────────────────────
echo ""
echo "=== parse_command_and_output ==="

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  CMD=""
  TOOL_OUTPUT=""
  JSON='{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"output":"On branch main"}}'
  if parse_command_and_output "$JSON"; then
    if [ "$CMD" = "git status" ] && [ "$TOOL_OUTPUT" = "On branch main" ]; then
      echo "  ✓ extracts command and output"
    else
      echo "  ✗ CMD='$CMD', TOOL_OUTPUT='$TOOL_OUTPUT'"
    fi
  else
    echo "  ✗ returned failure on valid JSON"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  CMD=""
  TOOL_OUTPUT=""
  JSON='{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":"file1\nfile2"}'
  if parse_command_and_output "$JSON"; then
    if [ "$CMD" = "ls" ]; then
      echo "  ✓ handles string tool_response"
    else
      echo "  ✗ CMD='$CMD'"
    fi
  else
    echo "  ✗ returned failure"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  CMD=""
  JSON='invalid'
  if parse_command_and_output "$JSON"; then
    echo "  ✗ should have returned failure on invalid JSON"
  else
    echo "  ✓ returns failure on invalid JSON"
  fi
)

# ── Test: split_commands ─────────────────────────────────────────────────────
echo ""
echo "=== split_commands ==="

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  result=$(split_commands "git add . && git commit -m test")
  lines=$(echo "$result" | wc -l | tr -d ' ')
  first=$(echo "$result" | head -1)
  second=$(echo "$result" | tail -1)
  if [ "$lines" = "2" ] && [ "$first" = "git add ." ] && [ "$second" = "git commit -m test" ]; then
    echo "  ✓ splits on &&"
  else
    echo "  ✗ got $lines lines: '$result'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  result=$(split_commands "echo a || echo b")
  lines=$(echo "$result" | wc -l | tr -d ' ')
  if [ "$lines" = "2" ]; then
    echo "  ✓ splits on ||"
  else
    echo "  ✗ got $lines lines"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  result=$(split_commands "echo a; echo b; echo c")
  lines=$(echo "$result" | wc -l | tr -d ' ')
  if [ "$lines" = "3" ]; then
    echo "  ✓ splits on semicolons"
  else
    echo "  ✗ got $lines lines"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  result=$(split_commands "git status")
  if [ "$result" = "git status" ]; then
    echo "  ✓ returns original when no separators"
  else
    echo "  ✗ got '$result'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  result=$(split_commands "git add . && git commit -m test && git push origin main")
  lines=$(echo "$result" | wc -l | tr -d ' ')
  if [ "$lines" = "3" ]; then
    echo "  ✓ splits three chained commands"
  else
    echo "  ✗ got $lines lines"
  fi
)

# ── Test: current_branch ─────────────────────────────────────────────────────
echo ""
echo "=== current_branch ==="

setup_repo
(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"
  cd "$TMPDIR/repo"

  branch=$(current_branch)
  if [ "$branch" = "main" ]; then
    echo "  ✓ returns branch name"
  else
    echo "  ✗ expected 'main', got '$branch'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"
  cd "$TMPDIR/repo"
  git checkout -b feature/test >/dev/null 2>&1

  branch=$(current_branch)
  if [ "$branch" = "feature/test" ]; then
    echo "  ✓ returns feature branch name"
  else
    echo "  ✗ expected 'feature/test', got '$branch'"
  fi
)

# ── Test: is_main_branch ─────────────────────────────────────────────────────
echo ""
echo "=== is_main_branch ==="

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  if is_main_branch "main"; then
    echo "  ✓ returns 0 for 'main'"
  else
    echo "  ✗ should return 0 for 'main'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  if is_main_branch "master"; then
    echo "  ✓ returns 0 for 'master'"
  else
    echo "  ✗ should return 0 for 'master'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  if is_main_branch "feature/test"; then
    echo "  ✗ should return 1 for 'feature/test'"
  else
    echo "  ✓ returns 1 for 'feature/test'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  if is_main_branch "develop"; then
    echo "  ✗ should return 1 for 'develop'"
  else
    echo "  ✓ returns 1 for 'develop'"
  fi
)

# ── Test: read_config ────────────────────────────────────────────────────────
echo ""
echo "=== read_config ==="

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"
  cd "$TMPDIR"
  mkdir -p .claude
  echo "EXPLAIN_SCOPE=all" > .claude/githabits.conf
  echo "WORKFLOW_NUDGE=off" >> .claude/githabits.conf

  val=$(read_config "EXPLAIN_SCOPE" "git")
  if [ "$val" = "all" ]; then
    echo "  ✓ reads EXPLAIN_SCOPE from config"
  else
    echo "  ✗ expected 'all', got '$val'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"
  cd "$TMPDIR"
  mkdir -p .claude
  echo "EXPLAIN_SCOPE=all" > .claude/githabits.conf
  echo "WORKFLOW_NUDGE=off" >> .claude/githabits.conf

  val=$(read_config "WORKFLOW_NUDGE" "on")
  if [ "$val" = "off" ]; then
    echo "  ✓ reads WORKFLOW_NUDGE from config"
  else
    echo "  ✗ expected 'off', got '$val'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"
  cd "$TMPDIR"
  rm -rf .claude/githabits.conf 2>/dev/null || true

  val=$(read_config "MISSING_KEY" "default_val")
  if [ "$val" = "default_val" ]; then
    echo "  ✓ returns default when key missing"
  else
    echo "  ✗ expected 'default_val', got '$val'"
  fi
)

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"

  # Use a directory with no config file at all
  cd /tmp
  val=$(HOME=/nonexistent read_config "EXPLAIN_SCOPE" "git")
  if [ "$val" = "git" ]; then
    echo "  ✓ returns default when no config file exists"
  else
    echo "  ✗ expected 'git', got '$val'"
  fi
)

# ── Test: double-source guard ────────────────────────────────────────────────
echo ""
echo "=== double-source guard ==="

(
  unset _GITHABITS_LIB_LOADED
  source "$LIB"
  if [ "$_GITHABITS_LIB_LOADED" = "1" ]; then
    echo "  ✓ sets _GITHABITS_LIB_LOADED on first source"
  else
    echo "  ✗ guard variable not set"
  fi

  # Source again — should not error
  source "$LIB"
  echo "  ✓ second source does not error"
)

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
# Count results from output
TOTAL_PASS=$(grep -c '✓' /dev/stdin <<< "$(bash "$0" 2>&1)" 2>/dev/null || true)
echo "=== Shared library tests complete ==="
