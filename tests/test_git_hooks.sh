#!/usr/bin/env bash
# Tests for native git hooks (hooks/git-hooks/*)
# Runs each hook in an isolated git repo to verify blocking/hints.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/../hooks/git-hooks"
LIB_DIR="$SCRIPT_DIR/../lib"

RESULTS_FILE=""  # set in setup

pass() { echo "  ✓ $1"; echo "PASS" >> "$RESULTS_FILE"; }
fail() { echo "  ✗ $1"; echo "FAIL" >> "$RESULTS_FILE"; }

# ── Setup ────────────────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
RESULTS_FILE="$TMPDIR/results.log"
touch "$RESULTS_FILE"
export RESULTS_FILE

# Create a fake home so hooks find the lib
FAKEHOME="$TMPDIR/fakehome"
mkdir -p "$FAKEHOME/.githabits/lib"
cp "$LIB_DIR/githabits.sh" "$FAKEHOME/.githabits/lib/githabits.sh"

setup_repo() {
  rm -rf "$TMPDIR/repo"
  mkdir -p "$TMPDIR/repo"
  (
    cd "$TMPDIR/repo"
    git init -b main >/dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "init" > file.txt
    git add .
    git commit -m "init" >/dev/null 2>&1
  )
}

# Install a specific git hook into the test repo
install_hook() {
  local hook_name="$1"
  mkdir -p "$TMPDIR/repo/.git/hooks"
  cp "$HOOKS_DIR/$hook_name" "$TMPDIR/repo/.git/hooks/$hook_name"
  chmod +x "$TMPDIR/repo/.git/hooks/$hook_name"
}

# ═══════════════════════════════════════════════════════════════════════════════
echo "=== pre-commit ==="

# T1: Block commit on main
setup_repo
install_hook "pre-commit"
(
  cd "$TMPDIR/repo"
  echo "change" > file.txt
  git add .
  OUTPUT=$(HOME="$FAKEHOME" git commit -m "test" 2>&1) && fail "T1: should block commit on main" || true
  if echo "$OUTPUT" | grep -q "commit on main"; then
    pass "T1: blocks commit on main with tutor message"
  else
    fail "T1: missing tutor message, got: $OUTPUT"
  fi
)

# T2: Allow commit on feature branch
setup_repo
install_hook "pre-commit"
(
  cd "$TMPDIR/repo"
  git checkout -b feature/test >/dev/null 2>&1
  echo "change" > file.txt
  git add .
  if HOME="$FAKEHOME" git commit -m "test on feature" >/dev/null 2>&1; then
    pass "T2: allows commit on feature branch"
  else
    fail "T2: blocked commit on feature branch"
  fi
)

# T3: GITHABITS_ALLOW_MAIN=1 bypass
setup_repo
install_hook "pre-commit"
(
  cd "$TMPDIR/repo"
  echo "change" > file.txt
  git add .
  if HOME="$FAKEHOME" GITHABITS_ALLOW_MAIN=1 git commit -m "bypass test" >/dev/null 2>&1; then
    pass "T3: GITHABITS_ALLOW_MAIN=1 allows commit on main"
  else
    fail "T3: GITHABITS_ALLOW_MAIN=1 did not bypass"
  fi
)

# T4: Allow first commit in empty repo
(
  rm -rf "$TMPDIR/empty-repo"
  mkdir -p "$TMPDIR/empty-repo"
  cd "$TMPDIR/empty-repo"
  git init -b main >/dev/null 2>&1
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .git/hooks
  cp "$HOOKS_DIR/pre-commit" .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  echo "first" > file.txt
  git add .
  if HOME="$FAKEHOME" git commit -m "initial commit" >/dev/null 2>&1; then
    pass "T4: allows first commit in empty repo on main"
  else
    fail "T4: blocked first commit in empty repo"
  fi
)

# T5: Block commit on master
setup_repo
(
  cd "$TMPDIR/repo"
  git branch -m main master >/dev/null 2>&1
  install_hook "pre-commit"
  echo "change" > file.txt
  git add .
  OUTPUT=$(HOME="$FAKEHOME" git commit -m "test" 2>&1) && fail "T5: should block on master" || true
  if echo "$OUTPUT" | grep -q "commit on master"; then
    pass "T5: blocks commit on master"
  else
    fail "T5: missing block message for master, got: $OUTPUT"
  fi
)

# T6: Detached HEAD
setup_repo
install_hook "pre-commit"
(
  cd "$TMPDIR/repo"
  COMMIT=$(git rev-parse HEAD)
  git checkout "$COMMIT" >/dev/null 2>&1
  echo "change" > file.txt
  git add .
  OUTPUT=$(HOME="$FAKEHOME" git commit -m "detached" 2>&1) && fail "T6: should block detached HEAD" || true
  if echo "$OUTPUT" | grep -q "detached HEAD"; then
    pass "T6: blocks commit in detached HEAD state"
  else
    fail "T6: missing detached HEAD message, got: $OUTPUT"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== pre-push ==="

# T7: Block push to main
setup_repo
install_hook "pre-push"
(
  cd "$TMPDIR/repo"
  # Create a bare remote
  git clone --bare . "$TMPDIR/remote.git" >/dev/null 2>&1
  git remote remove origin 2>/dev/null || true
  git remote add origin "$TMPDIR/remote.git"
  echo "change" > file.txt
  git add .
  GITHABITS_ALLOW_MAIN=1 git commit -m "change" >/dev/null 2>&1  # bypass pre-commit if installed
  OUTPUT=$(HOME="$FAKEHOME" git push origin main 2>&1) && fail "T7: should block push to main" || true
  if echo "$OUTPUT" | grep -q "push to main"; then
    pass "T7: blocks push to main"
  else
    fail "T7: missing block message, got: $OUTPUT"
  fi
)

# T8: Allow push to feature branch
setup_repo
install_hook "pre-push"
install_hook "pre-commit"
(
  cd "$TMPDIR/repo"
  git clone --bare . "$TMPDIR/remote2.git" >/dev/null 2>&1
  git remote remove origin 2>/dev/null || true
  git remote add origin "$TMPDIR/remote2.git"
  git checkout -b feature/test >/dev/null 2>&1
  echo "change" > file.txt
  git add .
  HOME="$FAKEHOME" git commit -m "feature change" >/dev/null 2>&1
  if HOME="$FAKEHOME" git push origin feature/test >/dev/null 2>&1; then
    pass "T8: allows push to feature branch"
  else
    fail "T8: blocked push to feature branch"
  fi
)

# T9: GITHABITS_ALLOW_MAIN=1 bypass for push
setup_repo
install_hook "pre-push"
(
  cd "$TMPDIR/repo"
  git clone --bare . "$TMPDIR/remote3.git" >/dev/null 2>&1
  git remote remove origin 2>/dev/null || true
  git remote add origin "$TMPDIR/remote3.git"
  echo "change" > file.txt
  git add .
  GITHABITS_ALLOW_MAIN=1 git commit -m "change" >/dev/null 2>&1
  if HOME="$FAKEHOME" GITHABITS_ALLOW_MAIN=1 git push origin main >/dev/null 2>&1; then
    pass "T9: GITHABITS_ALLOW_MAIN=1 allows push to main"
  else
    fail "T9: GITHABITS_ALLOW_MAIN=1 did not bypass push"
  fi
)

# T10: Block push to master
setup_repo
(
  cd "$TMPDIR/repo"
  git branch -m main master >/dev/null 2>&1
  install_hook "pre-push"
  git clone --bare . "$TMPDIR/remote4.git" >/dev/null 2>&1
  git remote remove origin 2>/dev/null || true
  git remote add origin "$TMPDIR/remote4.git"
  echo "change" > file.txt
  git add .
  GITHABITS_ALLOW_MAIN=1 git commit -m "change" >/dev/null 2>&1
  OUTPUT=$(HOME="$FAKEHOME" git push origin master 2>&1) && fail "T10: should block push to master" || true
  if echo "$OUTPUT" | grep -q "push to master"; then
    pass "T10: blocks push to master"
  else
    fail "T10: missing block message for master, got: $OUTPUT"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== post-commit ==="

# T11: Hint after commit on feature branch
setup_repo
install_hook "post-commit"
(
  cd "$TMPDIR/repo"
  git checkout -b feature/test >/dev/null 2>&1
  echo "change" > file.txt
  git add .
  OUTPUT=$(HOME="$FAKEHOME" git commit -m "test commit" 2>&1)
  if echo "$OUTPUT" | grep -q "push to GitHub"; then
    pass "T11: shows push hint after feature branch commit"
  else
    fail "T11: missing push hint, got: $OUTPUT"
  fi
)

# T12: No hint on main (post-commit shouldn't fire a hint for main)
setup_repo
install_hook "post-commit"
(
  cd "$TMPDIR/repo"
  echo "change" > file.txt
  git add .
  # Bypass pre-commit blocking
  OUTPUT=$(HOME="$FAKEHOME" GITHABITS_ALLOW_MAIN=1 git commit -m "main commit" 2>&1)
  if echo "$OUTPUT" | grep -q "push to GitHub"; then
    fail "T12: should not show push hint on main"
  else
    pass "T12: no push hint on main commit"
  fi
)

# T13: Hint includes branch name
setup_repo
install_hook "post-commit"
(
  cd "$TMPDIR/repo"
  git checkout -b feature/my-thing >/dev/null 2>&1
  echo "change" > file.txt
  git add .
  OUTPUT=$(HOME="$FAKEHOME" git commit -m "test" 2>&1)
  if echo "$OUTPUT" | grep -q "feature/my-thing"; then
    pass "T13: hint includes branch name"
  else
    fail "T13: hint missing branch name, got: $OUTPUT"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== post-checkout ==="

# T14: Hint when switching to feature branch
setup_repo
install_hook "post-checkout"
(
  cd "$TMPDIR/repo"
  git checkout -b feature/test >/dev/null 2>&1  # creates branch first
  git checkout main >/dev/null 2>&1
  OUTPUT=$(HOME="$FAKEHOME" git checkout feature/test 2>&1)
  if echo "$OUTPUT" | grep -q "Start making changes"; then
    pass "T14: shows feature branch hint"
  else
    fail "T14: missing feature branch hint, got: $OUTPUT"
  fi
)

# T15: Hint when switching to main
setup_repo
install_hook "post-checkout"
(
  cd "$TMPDIR/repo"
  git checkout -b feature/test >/dev/null 2>&1
  OUTPUT=$(HOME="$FAKEHOME" git checkout main 2>&1)
  if echo "$OUTPUT" | grep -q "Create a feature branch"; then
    pass "T15: shows create-branch hint on main"
  else
    fail "T15: missing create-branch hint on main, got: $OUTPUT"
  fi
)

# T16: Hint when creating new branch (checkout -b)
setup_repo
install_hook "post-checkout"
(
  cd "$TMPDIR/repo"
  OUTPUT=$(HOME="$FAKEHOME" git checkout -b feature/new-thing 2>&1)
  if echo "$OUTPUT" | grep -q "Start making changes"; then
    pass "T16: shows hint when creating new branch"
  else
    fail "T16: missing hint on branch creation, got: $OUTPUT"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== post-merge ==="

# T17: Hint after pull on main
setup_repo
install_hook "post-merge"
(
  cd "$TMPDIR/repo"
  # Create a remote with an extra commit
  git clone --bare . "$TMPDIR/merge-remote.git" >/dev/null 2>&1
  git remote remove origin 2>/dev/null || true
  git remote add origin "$TMPDIR/merge-remote.git"
  # Create a commit on the remote
  (
    cd "$TMPDIR"
    git clone merge-remote.git merge-clone >/dev/null 2>&1
    cd merge-clone
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "remote change" > remote.txt
    git add .
    git commit -m "remote commit" >/dev/null 2>&1
    git push >/dev/null 2>&1
  )
  OUTPUT=$(HOME="$FAKEHOME" git pull origin main 2>&1)
  if echo "$OUTPUT" | grep -q "Ready for your next feature"; then
    pass "T17: shows next-feature hint after pull on main"
  else
    fail "T17: missing next-feature hint, got: $OUTPUT"
  fi
)

# T18: No hint after pull on feature branch
setup_repo
install_hook "post-merge"
(
  cd "$TMPDIR/repo"
  git checkout -b feature/test >/dev/null 2>&1
  git clone --bare . "$TMPDIR/merge-remote2.git" >/dev/null 2>&1
  git remote remove origin 2>/dev/null || true
  git remote add origin "$TMPDIR/merge-remote2.git"
  # Create extra commit on remote
  (
    cd "$TMPDIR"
    rm -rf merge-clone2
    git clone merge-remote2.git merge-clone2 >/dev/null 2>&1
    cd merge-clone2
    git config user.email "test@test.com"
    git config user.name "Test"
    git checkout feature/test >/dev/null 2>&1
    echo "remote change" > remote.txt
    git add .
    git commit -m "remote commit" >/dev/null 2>&1
    git push origin feature/test >/dev/null 2>&1
  )
  OUTPUT=$(HOME="$FAKEHOME" git pull origin feature/test 2>&1)
  if echo "$OUTPUT" | grep -q "Ready for your next feature"; then
    fail "T18: should not show next-feature hint on feature branch pull"
  else
    pass "T18: no next-feature hint on feature branch pull"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== emit_block_tty / emit_hint_tty formatting ==="

# T19: Block message has box drawing characters
setup_repo
install_hook "pre-commit"
(
  cd "$TMPDIR/repo"
  echo "change" > file.txt
  git add .
  OUTPUT=$(HOME="$FAKEHOME" git commit -m "test" 2>&1) || true
  if echo "$OUTPUT" | grep -q "╔"; then
    pass "T19: block message has box-drawing border"
  else
    fail "T19: missing box-drawing border, got: $OUTPUT"
  fi
)

# T20: Hint message has [GitHabits] prefix
setup_repo
install_hook "post-commit"
(
  cd "$TMPDIR/repo"
  git checkout -b feature/test >/dev/null 2>&1
  echo "change" > file.txt
  git add .
  OUTPUT=$(HOME="$FAKEHOME" git commit -m "test" 2>&1)
  if echo "$OUTPUT" | grep -q "\[GitHabits\]"; then
    pass "T20: hint message has [GitHabits] prefix"
  else
    fail "T20: missing [GitHabits] prefix, got: $OUTPUT"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== lib not found (graceful exit) ==="

# T21: Hook exits 0 when lib not found (doesn't block)
setup_repo
(
  cd "$TMPDIR/repo"
  mkdir -p .git/hooks
  cp "$HOOKS_DIR/pre-commit" .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  echo "change" > file.txt
  git add .
  # Use a HOME with no lib installed
  EMPTY_HOME="$TMPDIR/empty-home"
  mkdir -p "$EMPTY_HOME"
  if HOME="$EMPTY_HOME" git commit -m "no lib test" >/dev/null 2>&1; then
    pass "T21: pre-commit exits 0 when lib not found"
  else
    fail "T21: pre-commit blocked when lib not found"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== setup.sh git hooks installation ==="

# T22: setup.sh --git-hooks creates template directory
SETUP="$SCRIPT_DIR/../setup.sh"
(
  INSTALL_HOME="$TMPDIR/install-home"
  mkdir -p "$INSTALL_HOME"
  # Run setup with --git-hooks in non-interactive mode
  HOME="$INSTALL_HOME" bash "$SETUP" --git-hooks \
    --explain-scope=none --workflow-nudge=off </dev/null 2>&1 || true
  if [ -d "$INSTALL_HOME/.githabits/template/hooks" ]; then
    pass "T22: --git-hooks creates template/hooks directory"
  else
    fail "T22: template/hooks directory not created"
  fi
)

# T23: setup.sh --git-hooks copies all hook scripts
(
  INSTALL_HOME="$TMPDIR/install-home"
  EXPECTED_HOOKS="pre-commit pre-push post-commit post-checkout post-merge"
  ALL_FOUND=true
  for h in $EXPECTED_HOOKS; do
    if [ ! -f "$INSTALL_HOME/.githabits/template/hooks/$h" ]; then
      ALL_FOUND=false
      fail "T23: missing hook $h"
    fi
  done
  if [ "$ALL_FOUND" = true ]; then
    pass "T23: all 5 git hook scripts installed"
  fi
)

# T24: setup.sh --git-hooks copies shared library
(
  INSTALL_HOME="$TMPDIR/install-home"
  if [ -f "$INSTALL_HOME/.githabits/lib/githabits.sh" ]; then
    pass "T24: shared library copied to ~/.githabits/lib/"
  else
    fail "T24: shared library not found in ~/.githabits/lib/"
  fi
)

# T25: Hook scripts are executable
(
  INSTALL_HOME="$TMPDIR/install-home"
  if [ -x "$INSTALL_HOME/.githabits/template/hooks/pre-commit" ]; then
    pass "T25: installed hooks are executable"
  else
    fail "T25: installed hooks are not executable"
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
