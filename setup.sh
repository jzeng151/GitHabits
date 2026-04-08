#!/usr/bin/env bash
# GitHabits setup script
# Installs the git pedagogy hook for Claude Code.
#
# Usage:
#   ./setup.sh             # global install (~/.claude/)
#   ./setup.sh --project   # per-project install (.claude/)
#   ./setup.sh --uninstall # remove all GitHabits files

set -euo pipefail

# ── Check Claude Code version ─────────────────────────────────────────────────
MIN_CLAUDE_VERSION="2.1.91"

check_claude_version() {
  if ! command -v claude >/dev/null 2>&1; then
    error "Claude Code is not installed."
    error "Install it from: https://claude.ai/code"
    exit 1
  fi

  local version
  version=$(claude --version 2>/dev/null | cut -d' ' -f1)

  if [ -z "$version" ]; then
    warn "Could not determine Claude Code version — skipping version check."
    return
  fi

  # sort -V: version-aware sort; if min sorts first, installed >= min
  local lower
  lower=$(printf '%s\n%s' "$MIN_CLAUDE_VERSION" "$version" | sort -V | head -n1)

  if [ "$lower" != "$MIN_CLAUDE_VERSION" ]; then
    echo ""
    error "GitHabits requires Claude Code v${MIN_CLAUDE_VERSION} or later."
    error "Your version: $version"
    echo ""
    echo "  The PreToolUse hook JSON+exit2 fix landed in v${MIN_CLAUDE_VERSION} (April 2, 2026)."
    echo "  On older versions the hook fires but the block doesn't work."
    echo ""
    echo "  To upgrade:  claude upgrade"
    echo ""
    printf "  Upgrade now and re-run, or continue anyway? [u=upgrade / c=continue]: "
    read -r REPLY
    case "$REPLY" in
      u|U)
        echo ""
        info "Running: claude upgrade"
        claude upgrade
        echo ""
        info "Re-run ./setup.sh after upgrade completes."
        exit 0
        ;;
      *)
        warn "Continuing with unsupported version — hook may not work correctly."
        ;;
    esac
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/hooks/pre_tool_use.sh"
POST_HOOK_SRC="$SCRIPT_DIR/hooks/post_tool_use.sh"
LIB_SRC="$SCRIPT_DIR/lib/githabits.sh"
CLAUDE_MD_SRC="$SCRIPT_DIR/templates/CLAUDE.md"
MARKER_START="# GitHabits START"
MARKER_END="# GitHabits END"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BOLD}$*${RESET}"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}!${RESET} $*"; }
error()   { echo -e "${RED}✗${RESET} $*" >&2; }

# ── Parse flags ───────────────────────────────────────────────────────────────
MODE="global"
UNINSTALL=false
EXPLAIN_SCOPE=""
WORKFLOW_NUDGE=""

for arg in "$@"; do
  case "$arg" in
    --project)   MODE="project" ;;
    --uninstall) UNINSTALL=true ;;
    --explain-scope=*)
      EXPLAIN_SCOPE="${arg#*=}"
      ;;
    --workflow-nudge=*)
      WORKFLOW_NUDGE="${arg#*=}"
      ;;
    --help|-h)
      echo "Usage: ./setup.sh [--project] [--uninstall] [--explain-scope=SCOPE]"
      echo "                  [--workflow-nudge=on|off]"
      echo ""
      echo "  (no flag)                Install globally in ~/.claude/"
      echo "  --project                Install in .claude/ (this project only)"
      echo "  --uninstall              Remove all GitHabits files and config"
      echo "  --explain-scope=SCOPE    Set explanation scope: all, git, dev, none"
      echo "  --workflow-nudge=on|off  Toggle workflow reminders"
      echo ""
      echo "  Flags can be used standalone to change settings after install."
      exit 0
      ;;
    *) error "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── Resolve install paths ─────────────────────────────────────────────────────
if [ "$MODE" = "global" ]; then
  CLAUDE_DIR="$HOME/.claude"
else
  CLAUDE_DIR="$(pwd)/.claude"
fi

HOOKS_DIR="$CLAUDE_DIR/hooks"
LIB_DIR="$CLAUDE_DIR/lib"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CLAUDE_MD_FILE="$CLAUDE_DIR/CLAUDE.md"
HOOK_DEST="$HOOKS_DIR/pre_tool_use.sh"
POST_HOOK_DEST="$HOOKS_DIR/post_tool_use.sh"
CONFIG_FILE="$CLAUDE_DIR/githabits.conf"

# ── Config helper ─────────────────────────────────────────────────────────────
# Update a single key in githabits.conf without clobbering other values.
update_config() {
  local key="$1" value="$2"
  mkdir -p "$CLAUDE_DIR"
  if [ -f "$CONFIG_FILE" ]; then
    grep -v "^${key}=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null || true
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  fi
  echo "${key}=${value}" >> "$CONFIG_FILE"
}

# ── Standalone config mode ───────────────────────────────────────────────────
# Allow changing settings without a full reinstall.
if [ "$UNINSTALL" = false ] && { [ -n "$EXPLAIN_SCOPE" ] || [ -n "$WORKFLOW_NUDGE" ]; }; then
  STANDALONE=true

  if [ -n "$EXPLAIN_SCOPE" ]; then
    case "$EXPLAIN_SCOPE" in
      all|git|dev|none) ;;
      *) error "Invalid scope: $EXPLAIN_SCOPE. Use: all, git, dev, none"; exit 1 ;;
    esac
    update_config "EXPLAIN_SCOPE" "$EXPLAIN_SCOPE"
    success "Explanation scope set to: $EXPLAIN_SCOPE"
    STANDALONE=false  # we handled it
  fi

  if [ -n "$WORKFLOW_NUDGE" ]; then
    case "$WORKFLOW_NUDGE" in
      on|off) ;;
      *) error "Invalid value: $WORKFLOW_NUDGE. Use: on, off"; exit 1 ;;
    esac
    update_config "WORKFLOW_NUDGE" "$WORKFLOW_NUDGE"
    success "Workflow nudge set to: $WORKFLOW_NUDGE"
    STANDALONE=false
  fi

  exit 0
fi

# ── Require python3 ───────────────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  error "python3 is required but not installed."
  error "Install it from https://python.org or via your package manager."
  exit 1
fi

# ── Uninstall ─────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
  info "Uninstalling GitHabits..."

  # Remove config file
  if [ -f "$CONFIG_FILE" ]; then
    rm -f "$CONFIG_FILE"
    success "Removed config: $CONFIG_FILE"
  fi

  # Remove shared library
  if [ -d "$LIB_DIR" ]; then
    rm -rf "$LIB_DIR"
    success "Removed library: $LIB_DIR"
  fi

  # Remove hook scripts
  for hook_file in "$HOOK_DEST" "$POST_HOOK_DEST"; do
    if [ -f "$hook_file" ]; then
      rm -f "$hook_file"
      success "Removed hook: $hook_file"
    fi
  done

  # Remove hook entries from settings.json
  if [ -f "$SETTINGS_FILE" ]; then
    python3 - "$SETTINGS_FILE" "$HOOK_DEST" "$POST_HOOK_DEST" <<'PYEOF'
import json, sys
path = sys.argv[1]
hook_cmds = sys.argv[2:]
with open(path) as f:
    cfg = json.load(f)
hooks = cfg.get("hooks", {})
for key in ["PreToolUse", "PostToolUse"]:
    entries = hooks.get(key, [])
    new_entries = []
    for entry in entries:
        sub = entry.get("hooks", [])
        sub = [h for h in sub if h.get("command") not in hook_cmds]
        if sub:
            entry["hooks"] = sub
            new_entries.append(entry)
    if new_entries:
        cfg["hooks"][key] = new_entries
    elif key in hooks:
        del cfg["hooks"][key]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
    success "Removed hook entries from: $SETTINGS_FILE"
  fi

  # Remove GitHabits block from CLAUDE.md
  if [ -f "$CLAUDE_MD_FILE" ] && grep -q "$MARKER_START" "$CLAUDE_MD_FILE" 2>/dev/null; then
    python3 - "$CLAUDE_MD_FILE" "$MARKER_START" "$MARKER_END" <<'PYEOF'
import sys
path, start, end = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    lines = f.readlines()
out, skip = [], False
for line in lines:
    if line.strip() == start:
        skip = True
    if not skip:
        out.append(line)
    if skip and line.strip() == end:
        skip = False
with open(path, "w") as f:
    f.writelines(out)
PYEOF
    success "Removed GitHabits block from: $CLAUDE_MD_FILE"
  fi

  echo ""
  success "GitHabits uninstalled."
  exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────
echo ""
info "Installing GitHabits (${MODE} mode)..."
echo ""

# Verify Claude Code version
check_claude_version

# Ask about explanation scope (unless already set via flag)
if [ -z "$EXPLAIN_SCOPE" ]; then
  echo ""
  echo "How much should Claude explain when running commands?"
  echo ""
  echo "  1) All commands    — explain every bash command (ls, npm, curl, etc.)"
  echo "  2) Git commands    — only explain git commands (recommended for git learners)"
  echo "  3) Dev tools       — git + npm, pip, curl, docker, chmod, mkdir, etc."
  echo "  4) None            — no automatic explanations"
  echo ""
  printf "  Choose [1-4, default: 2]: "
  read -r SCOPE_CHOICE
  case "$SCOPE_CHOICE" in
    1) EXPLAIN_SCOPE="all" ;;
    3) EXPLAIN_SCOPE="dev" ;;
    4) EXPLAIN_SCOPE="none" ;;
    *) EXPLAIN_SCOPE="git" ;;
  esac
  echo ""
fi

# Ask about workflow nudges (unless already set via flag)
if [ -z "$WORKFLOW_NUDGE" ]; then
  echo "Should Claude remind you about unfinished workflow steps?"
  echo ""
  echo "  1) On   — gentle reminders about unpushed commits, missing PRs (recommended)"
  echo "  2) Off  — no workflow reminders"
  echo ""
  printf "  Choose [1-2, default: 1]: "
  read -r NUDGE_CHOICE
  case "$NUDGE_CHOICE" in
    2) WORKFLOW_NUDGE="off" ;;
    *) WORKFLOW_NUDGE="on" ;;
  esac
  echo ""
fi

# Create directories
mkdir -p "$HOOKS_DIR"
mkdir -p "$LIB_DIR"
mkdir -p "$CLAUDE_DIR"

# Write config file
cat > "$CONFIG_FILE" <<EOF
EXPLAIN_SCOPE=$EXPLAIN_SCOPE
WORKFLOW_NUDGE=$WORKFLOW_NUDGE
EOF
success "Explanation scope: $EXPLAIN_SCOPE"
success "Workflow nudge: $WORKFLOW_NUDGE"

# 1. Install hook scripts
cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
success "Hook installed: $HOOK_DEST"

cp "$POST_HOOK_SRC" "$POST_HOOK_DEST"
chmod +x "$POST_HOOK_DEST"
success "Hook installed: $POST_HOOK_DEST"

# Install shared library
cp "$LIB_SRC" "$LIB_DIR/githabits.sh"
success "Library installed: $LIB_DIR/githabits.sh"

# 2. Register hooks in settings.json
# Registers both PreToolUse and PostToolUse (idempotent)
register_hook() {
  local hook_key="$1"
  local hook_cmd="$2"

  RESULT=$(python3 - "$SETTINGS_FILE" "$hook_key" "$hook_cmd" <<'PYEOF'
import json, sys
path, key, hook_cmd = sys.argv[1], sys.argv[2], sys.argv[3]

if not __import__('os').path.exists(path):
    cfg = {}
else:
    with open(path) as f:
        cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})
entries = hooks.setdefault(key, [])

# Check if already registered (idempotent)
for entry in entries:
    for h in entry.get("hooks", []):
        if h.get("command") == hook_cmd:
            print("already_registered")
            sys.exit(0)

# Find existing Bash matcher or create new entry
for entry in entries:
    if entry.get("matcher") == "Bash":
        entry.setdefault("hooks", []).append({"type": "command", "command": hook_cmd})
        break
else:
    entries.append({
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": hook_cmd}]
    })

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("registered")
PYEOF
  )
  if [ "$RESULT" = "already_registered" ]; then
    warn "$hook_key hook already registered (skipped)"
  else
    success "Registered $hook_key hook in: $SETTINGS_FILE"
  fi
}

register_hook "PreToolUse" "$HOOK_DEST"
register_hook "PostToolUse" "$POST_HOOK_DEST"

# 3. Inject CLAUDE.md rules (idempotent)
if [ -f "$CLAUDE_MD_FILE" ] && grep -q "$MARKER_START" "$CLAUDE_MD_FILE" 2>/dev/null; then
  warn "GitHabits rules already in $CLAUDE_MD_FILE (skipped)"
else
  echo "" >> "$CLAUDE_MD_FILE"
  cat "$CLAUDE_MD_SRC" >> "$CLAUDE_MD_FILE"
  success "Added GitHabits rules to: $CLAUDE_MD_FILE"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
info "GitHabits installed!"
echo ""
echo "What happens now:"
echo "  • Claude explains commands before running them (scope: $EXPLAIN_SCOPE)"
echo "  • Committing or pushing to main/master is blocked with a tutorial"
echo "  • You'll be guided to create a feature branch instead"
echo "  • After each git milestone, Claude suggests the next step in the workflow"
echo "  • Workflow nudges remind you about unfinished steps (nudge: $WORKFLOW_NUDGE)"
echo ""
echo "To change settings after install:"
echo "  ./setup.sh --explain-scope=all|git|dev|none"
echo "  ./setup.sh --workflow-nudge=on|off"
echo "To uninstall:  ./setup.sh --uninstall"
echo "To override (solo project):  GITHABITS_ALLOW_MAIN=1 (see README)"
echo ""
