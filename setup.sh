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

for arg in "$@"; do
  case "$arg" in
    --project)   MODE="project" ;;
    --uninstall) UNINSTALL=true ;;
    --help|-h)
      echo "Usage: ./setup.sh [--project] [--uninstall]"
      echo ""
      echo "  (no flag)    Install globally in ~/.claude/"
      echo "  --project    Install in .claude/ (this project only)"
      echo "  --uninstall  Remove all GitHabits files and config"
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
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CLAUDE_MD_FILE="$CLAUDE_DIR/CLAUDE.md"
HOOK_DEST="$HOOKS_DIR/pre_tool_use.sh"

# ── Require python3 ───────────────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  error "python3 is required but not installed."
  error "Install it from https://python.org or via your package manager."
  exit 1
fi

# ── Uninstall ─────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
  info "Uninstalling GitHabits..."

  # Remove hook script
  if [ -f "$HOOK_DEST" ]; then
    rm -f "$HOOK_DEST"
    success "Removed hook: $HOOK_DEST"
  fi

  # Remove hook entry from settings.json
  if [ -f "$SETTINGS_FILE" ]; then
    python3 - "$SETTINGS_FILE" "$HOOK_DEST" <<'PYEOF'
import json, sys
path, hook_cmd = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
hooks = cfg.get("hooks", {})
ptu = hooks.get("PreToolUse", [])
new_ptu = []
for entry in ptu:
    sub = entry.get("hooks", [])
    sub = [h for h in sub if h.get("command") != hook_cmd]
    if sub:
        entry["hooks"] = sub
        new_ptu.append(entry)
if new_ptu:
    cfg["hooks"]["PreToolUse"] = new_ptu
elif "PreToolUse" in hooks:
    del cfg["hooks"]["PreToolUse"]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
    success "Removed hook entry from: $SETTINGS_FILE"
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

# Create directories
mkdir -p "$HOOKS_DIR"
mkdir -p "$CLAUDE_DIR"

# 1. Install hook script
cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
success "Hook installed: $HOOK_DEST"

# 2. Register hook in settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  # Create from scratch
  python3 - "$SETTINGS_FILE" "$HOOK_DEST" <<'PYEOF'
import json, sys
path, hook_cmd = sys.argv[1], sys.argv[2]
cfg = {
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": hook_cmd}]
      }
    ]
  }
}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
  success "Created: $SETTINGS_FILE"
else
  # Merge into existing settings.json (idempotent)
  RESULT=$(python3 - "$SETTINGS_FILE" "$HOOK_DEST" <<'PYEOF'
import json, sys
path, hook_cmd = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})
ptu = hooks.setdefault("PreToolUse", [])

# Check if already registered (idempotent)
for entry in ptu:
    for h in entry.get("hooks", []):
        if h.get("command") == hook_cmd:
            print("already_registered")
            sys.exit(0)

# Find existing Bash matcher or create new entry
for entry in ptu:
    if entry.get("matcher") == "Bash":
        entry.setdefault("hooks", []).append({"type": "command", "command": hook_cmd})
        break
else:
    ptu.append({
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
    warn "Hook already registered in $SETTINGS_FILE (skipped)"
  else
    success "Registered hook in: $SETTINGS_FILE"
  fi
fi

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
echo "  • Claude Code will explain every git command before running it"
echo "  • Committing or pushing to main/master is blocked with a tutorial"
echo "  • You'll be guided to create a feature branch instead"
echo ""
echo "To uninstall:  ./setup.sh --uninstall"
echo "To override (solo project):  GITHABITS_ALLOW_MAIN=1 (see README)"
echo ""
