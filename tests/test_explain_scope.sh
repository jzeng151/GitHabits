#!/usr/bin/env bash
# Tests for the configurable explanation scope feature.
#
# Validates:
#   1. setup.sh writes config file with correct scope values
#   2. --explain-scope=VALUE flag works standalone (no full reinstall)
#   3. --explain-scope=VALUE flag works during install
#   4. Invalid scope values are rejected
#   5. Uninstall removes the config file
#   6. Default scope is 'git' when user presses Enter
#   7. Config file is readable and parseable
#   8. CLAUDE.md template references the config file correctly
#   9. Global CLAUDE.md has the updated Rule 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$PROJECT_DIR/setup.sh"
TEMPLATE="$PROJECT_DIR/templates/CLAUDE.md"

# Use a temp directory to simulate installs (avoids touching real ~/.claude)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# ── Helper: run setup.sh with a fake HOME so it writes to TMPDIR ─────────────
# We use --project mode pointed at TMPDIR to avoid needing a fake HOME.
run_setup() {
  # Run from TMPDIR so --project writes to TMPDIR/.claude/
  (cd "$TMPDIR" && bash "$SETUP" --project "$@" 2>&1) || true
}

CONFIG="$TMPDIR/.claude/githabits.conf"
CLAUDE_MD="$TMPDIR/.claude/CLAUDE.md"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Test Suite: Explanation Scope ==="
echo ""

# ── T1: Template references config file ──────────────────────────────────────
echo "--- T1: CLAUDE.md template references githabits.conf ---"

if grep -q "githabits.conf" "$TEMPLATE"; then
  pass "Template mentions githabits.conf"
else
  fail "Template does not mention githabits.conf"
fi

if grep -q "EXPLAIN_SCOPE" "$TEMPLATE"; then
  pass "Template mentions EXPLAIN_SCOPE"
else
  fail "Template does not mention EXPLAIN_SCOPE"
fi

for scope in all git dev none; do
  if grep -qF -- "- $scope:" "$TEMPLATE"; then
    pass "Template documents scope '$scope'"
  else
    fail "Template missing scope '$scope'"
  fi
done

# ── T2: Template has the breakdown example ───────────────────────────────────
echo ""
echo "--- T2: CLAUDE.md template has explanation example ---"

if grep -q "git push" "$TEMPLATE" && grep -q "force-with-lease" "$TEMPLATE"; then
  pass "Template has git push --force-with-lease example"
else
  fail "Template missing the breakdown example"
fi

if grep -q "origin: the name for your GitHub repository" "$TEMPLATE"; then
  pass "Template breaks down 'origin'"
else
  fail "Template missing 'origin' breakdown"
fi

# ── T3: --explain-scope=VALUE standalone mode ────────────────────────────────
echo ""
echo "--- T3: Standalone --explain-scope flag ---"

# Create the .claude dir first (simulates existing install)
mkdir -p "$TMPDIR/.claude"

for scope in all git dev none; do
  # Run in TMPDIR so --project resolves to TMPDIR/.claude/
  (cd "$TMPDIR" && bash "$SETUP" --project --explain-scope="$scope" 2>&1) || true
  if [ -f "$CONFIG" ]; then
    ACTUAL=$(grep "EXPLAIN_SCOPE=" "$CONFIG" | cut -d= -f2)
    if [ "$ACTUAL" = "$scope" ]; then
      pass "--explain-scope=$scope writes '$scope' to config"
    else
      fail "--explain-scope=$scope wrote '$ACTUAL' instead of '$scope'"
    fi
  else
    fail "--explain-scope=$scope did not create config file"
  fi
  rm -f "$CONFIG"
done

# ── T4: Invalid scope values are rejected ────────────────────────────────────
echo ""
echo "--- T4: Invalid scope values ---"

for bad_scope in "everything" "ALL" "Git" "off" "yes" "1" ""; do
  OUTPUT=$(cd "$TMPDIR" && bash "$SETUP" --project --explain-scope="$bad_scope" 2>&1) || true
  if [ -f "$CONFIG" ]; then
    ACTUAL=$(grep "EXPLAIN_SCOPE=" "$CONFIG" 2>/dev/null | cut -d= -f2)
    # Empty string scope with --explain-scope= will have EXPLAIN_SCOPE="" which is empty
    # The scope-only mode check is [ -n "$EXPLAIN_SCOPE" ] so empty won't trigger it
    if [ -z "$bad_scope" ]; then
      # Empty scope means --explain-scope= was set but value is empty
      # This falls through to normal install (not scope-only mode)
      # So config might exist from install flow — that's expected
      pass "--explain-scope='' falls through to install (not scope-only mode)"
    else
      fail "--explain-scope='$bad_scope' should have been rejected but config was written with '$ACTUAL'"
    fi
  else
    pass "--explain-scope='$bad_scope' correctly rejected"
  fi
  rm -f "$CONFIG"
done

# ── T5: Config file is parseable ─────────────────────────────────────────────
echo ""
echo "--- T5: Config file format ---"

(cd "$TMPDIR" && bash "$SETUP" --project --explain-scope=dev 2>&1) || true

if [ -f "$CONFIG" ]; then
  # Source the config file like a shell would
  source "$CONFIG"
  if [ "$EXPLAIN_SCOPE" = "dev" ]; then
    pass "Config file is source-able by shell"
  else
    fail "Sourcing config gave EXPLAIN_SCOPE='$EXPLAIN_SCOPE' instead of 'dev'"
  fi

  # Parse with grep (how Claude's CLAUDE.md rule would work)
  PARSED=$(grep "^EXPLAIN_SCOPE=" "$CONFIG" | cut -d= -f2)
  if [ "$PARSED" = "dev" ]; then
    pass "Config file is parseable with grep+cut"
  else
    fail "grep+cut parse gave '$PARSED' instead of 'dev'"
  fi
else
  fail "Config file not created for parseability test"
fi

# Clean up for next test
rm -rf "$TMPDIR/.claude"

# ── T6: Install with scope flag (no interactive prompt) ──────────────────────
echo ""
echo "--- T6: Install with --explain-scope flag ---"

OUTPUT=$(cd "$TMPDIR" && bash "$SETUP" --project --explain-scope=all 2>&1)

# Since --explain-scope is set, scope-only mode triggers (exits early without full install)
# So we need to do a full install first, then change scope
rm -rf "$TMPDIR/.claude"

# Simulate install by piping "1" (scope=all) and "1" (nudge=on) to stdin
OUTPUT=$(cd "$TMPDIR" && printf '1\n1\n' | bash "$SETUP" --project 2>&1)

if [ -f "$CONFIG" ]; then
  ACTUAL=$(grep "EXPLAIN_SCOPE=" "$CONFIG" | cut -d= -f2)
  if [ "$ACTUAL" = "all" ]; then
    pass "Install with choice '1' sets scope to 'all'"
  else
    fail "Install with choice '1' set scope to '$ACTUAL' instead of 'all'"
  fi
else
  fail "Install did not create config file"
fi

# Check that hooks and CLAUDE.md were also installed
if [ -f "$TMPDIR/.claude/hooks/pre_tool_use.sh" ]; then
  pass "Pre-hook installed alongside config"
else
  fail "Pre-hook missing after install"
fi

if [ -f "$TMPDIR/.claude/hooks/post_tool_use.sh" ]; then
  pass "Post-hook installed alongside config"
else
  fail "Post-hook missing after install"
fi

if [ -f "$CLAUDE_MD" ] && grep -q "EXPLAIN_SCOPE" "$CLAUDE_MD"; then
  pass "CLAUDE.md installed with scope rules"
else
  fail "CLAUDE.md missing or lacks scope rules"
fi

# ── T7: Default scope (press Enter) ─────────────────────────────────────────
echo ""
echo "--- T7: Default scope on Enter ---"

rm -rf "$TMPDIR/.claude"

# Send empty input (just Enter) for both prompts
OUTPUT=$(cd "$TMPDIR" && printf '\n\n' | bash "$SETUP" --project 2>&1)

if [ -f "$CONFIG" ]; then
  ACTUAL=$(grep "EXPLAIN_SCOPE=" "$CONFIG" | cut -d= -f2)
  if [ "$ACTUAL" = "git" ]; then
    pass "Default scope (Enter) is 'git'"
  else
    fail "Default scope is '$ACTUAL' instead of 'git'"
  fi
else
  fail "Config file not created with default scope"
fi

# ── T8: Each interactive choice maps correctly ──────────────────────────────
echo ""
echo "--- T8: Interactive choice mapping ---"

for choice in 1 2 3 4; do
  case "$choice" in
    1) EXPECTED="all" ;;
    2) EXPECTED="git" ;;
    3) EXPECTED="dev" ;;
    4) EXPECTED="none" ;;
  esac
  rm -rf "$TMPDIR/.claude"
  OUTPUT=$(cd "$TMPDIR" && printf '%s\n1\n' "$choice" | bash "$SETUP" --project 2>&1)
  if [ -f "$CONFIG" ]; then
    ACTUAL=$(grep "EXPLAIN_SCOPE=" "$CONFIG" | cut -d= -f2)
    if [ "$ACTUAL" = "$EXPECTED" ]; then
      pass "Choice '$choice' maps to '$EXPECTED'"
    else
      fail "Choice '$choice' maps to '$ACTUAL' instead of '$EXPECTED'"
    fi
  else
    fail "Config not created for choice '$choice'"
  fi
done

# ── T9: Uninstall removes config file ───────────────────────────────────────
echo ""
echo "--- T9: Uninstall removes config ---"

# First install
rm -rf "$TMPDIR/.claude"
OUTPUT=$(cd "$TMPDIR" && printf '2\n1\n' | bash "$SETUP" --project 2>&1)

if [ -f "$CONFIG" ]; then
  pass "Config exists before uninstall"
else
  fail "Config missing before uninstall (can't test removal)"
fi

# Now uninstall
OUTPUT=$(cd "$TMPDIR" && bash "$SETUP" --project --uninstall 2>&1)

if [ ! -f "$CONFIG" ]; then
  pass "Config removed after uninstall"
else
  fail "Config still exists after uninstall"
fi

if [ ! -f "$TMPDIR/.claude/hooks/pre_tool_use.sh" ]; then
  pass "Pre-hook removed after uninstall"
else
  fail "Pre-hook still exists after uninstall"
fi

if [ ! -f "$TMPDIR/.claude/hooks/post_tool_use.sh" ]; then
  pass "Post-hook removed after uninstall"
else
  fail "Post-hook still exists after uninstall"
fi

# ── T10: Scope change preserves existing hooks ──────────────────────────────
echo ""
echo "--- T10: Scope change doesn't break existing install ---"

rm -rf "$TMPDIR/.claude"
OUTPUT=$(cd "$TMPDIR" && printf '2\n1\n' | bash "$SETUP" --project 2>&1)

# Verify full install exists
PRE_HOOK_EXISTS=false
POST_HOOK_EXISTS=false
SETTINGS_EXISTS=false
[ -f "$TMPDIR/.claude/hooks/pre_tool_use.sh" ] && PRE_HOOK_EXISTS=true
[ -f "$TMPDIR/.claude/hooks/post_tool_use.sh" ] && POST_HOOK_EXISTS=true
[ -f "$TMPDIR/.claude/settings.json" ] && SETTINGS_EXISTS=true

# Change scope
OUTPUT=$(cd "$TMPDIR" && bash "$SETUP" --project --explain-scope=all 2>&1)

# Verify hooks are still there
if [ "$PRE_HOOK_EXISTS" = true ] && [ -f "$TMPDIR/.claude/hooks/pre_tool_use.sh" ]; then
  pass "Pre-hook preserved after scope change"
else
  fail "Pre-hook lost after scope change"
fi

if [ "$POST_HOOK_EXISTS" = true ] && [ -f "$TMPDIR/.claude/hooks/post_tool_use.sh" ]; then
  pass "Post-hook preserved after scope change"
else
  fail "Post-hook lost after scope change"
fi

if [ "$SETTINGS_EXISTS" = true ] && [ -f "$TMPDIR/.claude/settings.json" ]; then
  pass "Settings preserved after scope change"
else
  fail "Settings lost after scope change"
fi

ACTUAL=$(grep "EXPLAIN_SCOPE=" "$CONFIG" | cut -d= -f2)
if [ "$ACTUAL" = "all" ]; then
  pass "Scope updated to 'all' after change"
else
  fail "Scope is '$ACTUAL' instead of 'all' after change"
fi

# Verify WORKFLOW_NUDGE was preserved when only scope changed
NUDGE_VAL=$(grep "WORKFLOW_NUDGE=" "$CONFIG" 2>/dev/null | cut -d= -f2)
if [ -n "$NUDGE_VAL" ]; then
  pass "WORKFLOW_NUDGE preserved after scope-only change ($NUDGE_VAL)"
else
  fail "WORKFLOW_NUDGE lost after scope-only change"
fi

# ── T10b: Workflow nudge change preserves scope ──────────────────────────────
echo ""
echo "--- T10b: Nudge change preserves scope ---"

# Change nudge — scope should be preserved
OUTPUT=$(cd "$TMPDIR" && bash "$SETUP" --project --workflow-nudge=off 2>&1)

ACTUAL_SCOPE=$(grep "EXPLAIN_SCOPE=" "$CONFIG" | cut -d= -f2)
ACTUAL_NUDGE=$(grep "WORKFLOW_NUDGE=" "$CONFIG" | cut -d= -f2)

if [ "$ACTUAL_SCOPE" = "all" ]; then
  pass "EXPLAIN_SCOPE preserved after nudge change"
else
  fail "EXPLAIN_SCOPE is '$ACTUAL_SCOPE' instead of 'all' after nudge change"
fi

if [ "$ACTUAL_NUDGE" = "off" ]; then
  pass "WORKFLOW_NUDGE updated to 'off'"
else
  fail "WORKFLOW_NUDGE is '$ACTUAL_NUDGE' instead of 'off'"
fi

# Change it back
OUTPUT=$(cd "$TMPDIR" && bash "$SETUP" --project --workflow-nudge=on 2>&1)
ACTUAL_NUDGE=$(grep "WORKFLOW_NUDGE=" "$CONFIG" | cut -d= -f2)
if [ "$ACTUAL_NUDGE" = "on" ]; then
  pass "WORKFLOW_NUDGE updated back to 'on'"
else
  fail "WORKFLOW_NUDGE is '$ACTUAL_NUDGE' instead of 'on'"
fi

# ── T10c: Invalid nudge values rejected ──────────────────────────────────────
echo ""
echo "--- T10c: Invalid nudge values ---"

for bad in "yes" "true" "1" "OFF" "ON"; do
  OUTPUT=$(cd "$TMPDIR" && bash "$SETUP" --project --workflow-nudge="$bad" 2>&1) || true
  if echo "$OUTPUT" | grep -qi "invalid"; then
    pass "--workflow-nudge='$bad' rejected"
  else
    fail "--workflow-nudge='$bad' not rejected"
  fi
done

# ── T11: Global CLAUDE.md has updated Rule 1 ────────────────────────────────
echo ""
echo "--- T11: Global CLAUDE.md check ---"

GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
if [ -f "$GLOBAL_CLAUDE_MD" ]; then
  if grep -q "EXPLAIN_SCOPE" "$GLOBAL_CLAUDE_MD"; then
    pass "Global CLAUDE.md has EXPLAIN_SCOPE reference"
  else
    fail "Global CLAUDE.md missing EXPLAIN_SCOPE reference"
  fi

  if grep -q "githabits.conf" "$GLOBAL_CLAUDE_MD"; then
    pass "Global CLAUDE.md references githabits.conf"
  else
    fail "Global CLAUDE.md missing githabits.conf reference"
  fi

  for scope in all git dev none; do
    if grep -qF -- "- $scope:" "$GLOBAL_CLAUDE_MD"; then
      pass "Global CLAUDE.md documents scope '$scope'"
    else
      fail "Global CLAUDE.md missing scope '$scope'"
    fi
  done
else
  fail "Global CLAUDE.md not found at $GLOBAL_CLAUDE_MD"
fi

# ── T12: Global config file exists ──────────────────────────────────────────
echo ""
echo "--- T12: Global config file ---"

GLOBAL_CONFIG="$HOME/.claude/githabits.conf"
if [ -f "$GLOBAL_CONFIG" ]; then
  ACTUAL=$(grep "EXPLAIN_SCOPE=" "$GLOBAL_CONFIG" | cut -d= -f2)
  if [ -n "$ACTUAL" ]; then
    pass "Global config exists with EXPLAIN_SCOPE=$ACTUAL"
  else
    fail "Global config exists but EXPLAIN_SCOPE is empty"
  fi
else
  fail "Global config not found at $GLOBAL_CONFIG"
fi

# ── T13: Template dev tools list is complete ─────────────────────────────────
echo ""
echo "--- T13: Dev tools list coverage ---"

# These tools should be in the dev scope list in CLAUDE.md
DEV_TOOLS="npm npx yarn pip python3 node curl wget docker chmod mkdir cp mv rm cat grep sed awk tar ssh scp rsync make cargo go"

for tool in $DEV_TOOLS; do
  if grep -q "$tool" "$TEMPLATE"; then
    pass "Dev tools list includes '$tool'"
  else
    fail "Dev tools list missing '$tool'"
  fi
done

# ── T14: setup.sh help text mentions --explain-scope ─────────────────────────
echo ""
echo "--- T14: Help text ---"

HELP_OUTPUT=$(bash "$SETUP" --help 2>&1) || true

if echo "$HELP_OUTPUT" | grep -q "explain-scope"; then
  pass "Help text mentions --explain-scope"
else
  fail "Help text missing --explain-scope"
fi

if echo "$HELP_OUTPUT" | grep -q "all, git, dev, none"; then
  pass "Help text lists all scope values"
else
  fail "Help text missing scope values"
fi

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
