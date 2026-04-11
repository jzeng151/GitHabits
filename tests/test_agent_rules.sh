#!/usr/bin/env bash
# Tests for agent rules templates and setup.sh --agents flag
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"
SETUP="$SCRIPT_DIR/../setup.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
RESULTS_FILE="$TMPDIR/results.log"
touch "$RESULTS_FILE"
export RESULTS_FILE

pass() { echo "  ✓ $1"; echo "PASS" >> "$RESULTS_FILE"; }
fail() { echo "  ✗ $1"; echo "FAIL" >> "$RESULTS_FILE"; }

# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Template existence ==="

# T1: AGENTS.md exists
if [ -f "$TEMPLATES_DIR/AGENTS.md" ]; then
  pass "T1: templates/AGENTS.md exists"
else
  fail "T1: templates/AGENTS.md missing"
fi

# T2: .goosehints exists
if [ -f "$TEMPLATES_DIR/.goosehints" ]; then
  pass "T2: templates/.goosehints exists"
else
  fail "T2: templates/.goosehints missing"
fi

# T3: Cursor rules exist
if [ -f "$TEMPLATES_DIR/cursor-rules/githabits.mdc" ]; then
  pass "T3: templates/cursor-rules/githabits.mdc exists"
else
  fail "T3: templates/cursor-rules/githabits.mdc missing"
fi

# T4: Windsurf rules exist
if [ -f "$TEMPLATES_DIR/windsurf-rules/githabits.md" ]; then
  pass "T4: templates/windsurf-rules/githabits.md exists"
else
  fail "T4: templates/windsurf-rules/githabits.md missing"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Template content — AGENTS.md ==="

AGENTS_MD="$TEMPLATES_DIR/AGENTS.md"

# T5: Has GitHabits markers
if grep -q "# GitHabits START" "$AGENTS_MD" && grep -q "# GitHabits END" "$AGENTS_MD"; then
  pass "T5: AGENTS.md has START/END markers"
else
  fail "T5: AGENTS.md missing markers"
fi

# T6: Has rule 1 (explain commands)
if grep -q "Explain git commands" "$AGENTS_MD"; then
  pass "T6: AGENTS.md has explain commands rule"
else
  fail "T6: AGENTS.md missing explain commands rule"
fi

# T7: Has rule 2 (check branch)
if grep -q "Check branch before committing" "$AGENTS_MD"; then
  pass "T7: AGENTS.md has check branch rule"
else
  fail "T7: AGENTS.md missing check branch rule"
fi

# T8: Has rule 3 (describe history)
if grep -q "Describe git history" "$AGENTS_MD"; then
  pass "T8: AGENTS.md has describe history rule"
else
  fail "T8: AGENTS.md missing describe history rule"
fi

# T9: Has rule 4 (suggest next step)
if grep -q "Suggest the next workflow step" "$AGENTS_MD"; then
  pass "T9: AGENTS.md has suggest next step rule"
else
  fail "T9: AGENTS.md missing suggest next step rule"
fi

# T10: Has override documentation
if grep -q "GITHABITS_ALLOW_MAIN" "$AGENTS_MD"; then
  pass "T10: AGENTS.md documents GITHABITS_ALLOW_MAIN override"
else
  fail "T10: AGENTS.md missing override documentation"
fi

# T11: No Claude Code specific references
if grep -q "PostToolUse" "$AGENTS_MD" || grep -q "EXPLAIN_SCOPE" "$AGENTS_MD" || grep -q "githabits.conf" "$AGENTS_MD"; then
  fail "T11: AGENTS.md contains Claude Code-specific references"
else
  pass "T11: AGENTS.md has no Claude Code-specific references"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Template content — .goosehints ==="

GOOSEHINTS="$TEMPLATES_DIR/.goosehints"

# T12: Has markers
if grep -q "# GitHabits START" "$GOOSEHINTS" && grep -q "# GitHabits END" "$GOOSEHINTS"; then
  pass "T12: .goosehints has START/END markers"
else
  fail "T12: .goosehints missing markers"
fi

# T13: Has all 4 rules (abbreviated)
RULES_FOUND=0
grep -q "Explain git commands" "$GOOSEHINTS" && RULES_FOUND=$((RULES_FOUND + 1))
grep -q "Check branch" "$GOOSEHINTS" && RULES_FOUND=$((RULES_FOUND + 1))
grep -q "Describe git history" "$GOOSEHINTS" && RULES_FOUND=$((RULES_FOUND + 1))
grep -q "Suggest the next workflow" "$GOOSEHINTS" && RULES_FOUND=$((RULES_FOUND + 1))
if [ "$RULES_FOUND" -eq 4 ]; then
  pass "T13: .goosehints has all 4 rules"
else
  fail "T13: .goosehints has $RULES_FOUND/4 rules"
fi

# T14: Is concise (Goose charges per line)
LINE_COUNT=$(wc -l < "$GOOSEHINTS" | tr -d ' ')
if [ "$LINE_COUNT" -le 30 ]; then
  pass "T14: .goosehints is concise ($LINE_COUNT lines)"
else
  fail "T14: .goosehints too long ($LINE_COUNT lines, should be ≤30)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Template content — Cursor .mdc ==="

CURSOR_MDC="$TEMPLATES_DIR/cursor-rules/githabits.mdc"

# T15: Has YAML frontmatter
if head -1 "$CURSOR_MDC" | grep -q "^---$"; then
  pass "T15: Cursor .mdc has YAML frontmatter start"
else
  fail "T15: Cursor .mdc missing YAML frontmatter"
fi

# T16: Has trigger: always_on
if grep -q "trigger: always_on" "$CURSOR_MDC"; then
  pass "T16: Cursor .mdc has trigger: always_on"
else
  fail "T16: Cursor .mdc missing trigger: always_on"
fi

# T17: Has description field
if grep -q "description:" "$CURSOR_MDC"; then
  pass "T17: Cursor .mdc has description field"
else
  fail "T17: Cursor .mdc missing description field"
fi

# T18: Has all 4 rules
RULES_FOUND=0
grep -q "Explain git commands" "$CURSOR_MDC" && RULES_FOUND=$((RULES_FOUND + 1))
grep -q "Check branch" "$CURSOR_MDC" && RULES_FOUND=$((RULES_FOUND + 1))
grep -q "Describe git history" "$CURSOR_MDC" && RULES_FOUND=$((RULES_FOUND + 1))
grep -q "Suggest the next workflow" "$CURSOR_MDC" && RULES_FOUND=$((RULES_FOUND + 1))
if [ "$RULES_FOUND" -eq 4 ]; then
  pass "T18: Cursor .mdc has all 4 rules"
else
  fail "T18: Cursor .mdc has $RULES_FOUND/4 rules"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Template content — Windsurf .md ==="

WINDSURF_MD="$TEMPLATES_DIR/windsurf-rules/githabits.md"

# T19: Has YAML frontmatter
if head -1 "$WINDSURF_MD" | grep -q "^---$"; then
  pass "T19: Windsurf .md has YAML frontmatter start"
else
  fail "T19: Windsurf .md missing YAML frontmatter"
fi

# T20: Has trigger: always_on
if grep -q "trigger: always_on" "$WINDSURF_MD"; then
  pass "T20: Windsurf .md has trigger: always_on"
else
  fail "T20: Windsurf .md missing trigger: always_on"
fi

# T21: Under 12K characters (Windsurf limit)
CHAR_COUNT=$(wc -c < "$WINDSURF_MD" | tr -d ' ')
if [ "$CHAR_COUNT" -le 12000 ]; then
  pass "T21: Windsurf .md under 12K chars ($CHAR_COUNT)"
else
  fail "T21: Windsurf .md exceeds 12K chars ($CHAR_COUNT)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== setup.sh --agents install ==="

# T22: --agents installs AGENTS.md
(
  cd "$TMPDIR"
  mkdir -p test-project && cd test-project
  git init -b main >/dev/null 2>&1
  HOME="$TMPDIR/fakehome" bash "$SETUP" --agents \
    --explain-scope=none --workflow-nudge=off </dev/null >/dev/null 2>&1 || true
  if [ -f "AGENTS.md" ] && grep -q "# GitHabits START" "AGENTS.md"; then
    pass "T22: --agents creates AGENTS.md with markers"
  else
    fail "T22: AGENTS.md not created or missing markers"
  fi
)

# T23: --agents is idempotent
(
  cd "$TMPDIR/test-project"
  HOME="$TMPDIR/fakehome" bash "$SETUP" --agents \
    --explain-scope=none --workflow-nudge=off </dev/null >/dev/null 2>&1 || true
  COUNT=$(grep -c "# GitHabits START" "AGENTS.md")
  if [ "$COUNT" -eq 1 ]; then
    pass "T23: --agents is idempotent (1 block after 2 installs)"
  else
    fail "T23: --agents not idempotent ($COUNT blocks found)"
  fi
)

# T24: --agents installs Cursor rules when .cursor/ exists
(
  cd "$TMPDIR"
  rm -rf cursor-project
  mkdir -p cursor-project/.cursor && cd cursor-project
  git init -b main >/dev/null 2>&1
  HOME="$TMPDIR/fakehome" bash "$SETUP" --agents \
    --explain-scope=none --workflow-nudge=off </dev/null >/dev/null 2>&1 || true
  if [ -f ".cursor/rules/githabits.mdc" ]; then
    pass "T24: --agents installs Cursor rules when .cursor/ exists"
  else
    fail "T24: Cursor rules not installed"
  fi
)

# T25: --agents installs Windsurf rules when .windsurf/ exists
(
  cd "$TMPDIR"
  rm -rf windsurf-project
  mkdir -p windsurf-project/.windsurf && cd windsurf-project
  git init -b main >/dev/null 2>&1
  HOME="$TMPDIR/fakehome" bash "$SETUP" --agents \
    --explain-scope=none --workflow-nudge=off </dev/null >/dev/null 2>&1 || true
  if [ -f ".windsurf/rules/githabits.md" ]; then
    pass "T25: --agents installs Windsurf rules when .windsurf/ exists"
  else
    fail "T25: Windsurf rules not installed"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== setup.sh --uninstall --agents ==="

# T26: Uninstall removes AGENTS.md block
(
  cd "$TMPDIR/test-project"
  HOME="$TMPDIR/fakehome" bash "$SETUP" --uninstall --agents </dev/null >/dev/null 2>&1 || true
  if [ -f "AGENTS.md" ] && grep -q "# GitHabits START" "AGENTS.md"; then
    fail "T26: AGENTS.md block not removed after uninstall"
  else
    pass "T26: --uninstall --agents removes AGENTS.md block"
  fi
)

# T27: Uninstall removes Cursor rules file
(
  cd "$TMPDIR/cursor-project"
  HOME="$TMPDIR/fakehome" bash "$SETUP" --uninstall --agents </dev/null >/dev/null 2>&1 || true
  if [ -f ".cursor/rules/githabits.mdc" ]; then
    fail "T27: Cursor rules file not removed after uninstall"
  else
    pass "T27: --uninstall --agents removes Cursor rules"
  fi
)

# T28: Uninstall removes Windsurf rules file
(
  cd "$TMPDIR/windsurf-project"
  HOME="$TMPDIR/fakehome" bash "$SETUP" --uninstall --agents </dev/null >/dev/null 2>&1 || true
  if [ -f ".windsurf/rules/githabits.md" ]; then
    fail "T28: Windsurf rules file not removed after uninstall"
  else
    pass "T28: --uninstall --agents removes Windsurf rules"
  fi
)

# T29: Uninstall preserves non-GitHabits content in AGENTS.md
(
  cd "$TMPDIR"
  rm -rf preserve-project
  mkdir -p preserve-project && cd preserve-project
  git init -b main >/dev/null 2>&1
  echo "# My Custom Rules" > AGENTS.md
  echo "Do not use tabs." >> AGENTS.md
  HOME="$TMPDIR/fakehome" bash "$SETUP" --agents \
    --explain-scope=none --workflow-nudge=off </dev/null >/dev/null 2>&1 || true
  HOME="$TMPDIR/fakehome" bash "$SETUP" --uninstall --agents </dev/null >/dev/null 2>&1 || true
  if grep -q "My Custom Rules" "AGENTS.md" && grep -q "Do not use tabs" "AGENTS.md"; then
    pass "T29: Uninstall preserves non-GitHabits content in AGENTS.md"
  else
    fail "T29: Uninstall damaged non-GitHabits content"
  fi
)

# T30: Uninstall on clean project is a no-op
(
  cd "$TMPDIR"
  rm -rf clean-project
  mkdir -p clean-project && cd clean-project
  git init -b main >/dev/null 2>&1
  HOME="$TMPDIR/fakehome" bash "$SETUP" --uninstall --agents </dev/null >/dev/null 2>&1
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 0 ]; then
    pass "T30: Uninstall on clean project exits 0"
  else
    fail "T30: Uninstall on clean project failed with exit $EXIT_CODE"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
PASS=$(grep -c "^PASS$" "$RESULTS_FILE" 2>/dev/null || true)
FAIL=$(grep -c "^FAIL$" "$RESULTS_FILE" 2>/dev/null || true)
PASS=${PASS:-0}
FAIL=${FAIL:-0}

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "════════════════════════════════════════"

[ "$FAIL" -eq 0 ] || exit 1
