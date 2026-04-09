#!/usr/bin/env bash
# GitHabits — shared library
# Sourced by hooks/pre_tool_use.sh and hooks/post_tool_use.sh
# Bash 3.2 compatible (macOS default). No associative arrays, no |&.

# Guard against double-sourcing
[ -n "${_GITHABITS_LIB_LOADED:-}" ] && return 0
_GITHABITS_LIB_LOADED=1

# ── JSON parsing ─────────────────────────────────────────────────────────────

# parse_command <json_string>
#   Sets global CMD to the parsed command string. Returns 1 if parse fails.
#   Use for PreToolUse hooks (only needs the command).
parse_command() {
  local stdin_json="$1"
  CMD=""
  if command -v python3 >/dev/null 2>&1; then
    CMD=$(python3 - "$stdin_json" <<'PYEOF'
import sys, json
try:
    data = json.loads(sys.argv[1])
    print(data["tool_input"]["command"])
except Exception:
    pass
PYEOF
    ) || true
  elif command -v jq >/dev/null 2>&1; then
    CMD=$(echo "$stdin_json" | jq -r '.tool_input.command' 2>/dev/null) || true
  fi
  [ -n "$CMD" ]
}

# parse_command_and_output <json_string>
#   Sets global CMD and TOOL_OUTPUT. Returns 1 if CMD is empty.
#   Use for PostToolUse hooks (needs command + tool response).
parse_command_and_output() {
  local stdin_json="$1"
  CMD=""
  TOOL_OUTPUT=""
  if command -v python3 >/dev/null 2>&1; then
    eval "$(python3 - "$stdin_json" <<'PYEOF'
import sys, json, shlex
try:
    data = json.loads(sys.argv[1])
    cmd = data["tool_input"]["command"]
    resp = data.get("tool_response", {})
    if isinstance(resp, dict):
        output = resp.get("output", resp.get("stdout", ""))
    else:
        output = str(resp) if resp else ""
    print("CMD=%s" % shlex.quote(cmd))
    print("TOOL_OUTPUT=%s" % shlex.quote(output))
except Exception:
    pass
PYEOF
    )" || true
  elif command -v jq >/dev/null 2>&1; then
    CMD=$(echo "$stdin_json" | jq -r '.tool_input.command' 2>/dev/null) || true
    TOOL_OUTPUT=$(echo "$stdin_json" | jq -r '.tool_response.output // .tool_response // ""' 2>/dev/null) || true
  fi
  [ -n "$CMD" ]
}

# ── Command splitting ────────────────────────────────────────────────────────

# split_commands <command_string>
#   Prints one sub-command per line (splits on &&, ||, ;).
#   Falls back to the original string if python3 is unavailable.
split_commands() {
  local cmd="$1"
  local result=""
  if command -v python3 >/dev/null 2>&1; then
    result=$(python3 - "$cmd" <<'PYEOF'
import sys, re
cmd = sys.argv[1]
parts = re.split(r'&&|\|\||;', cmd)
for p in parts:
    p = p.strip()
    if p:
        print(p)
PYEOF
    ) || result="$cmd"
  else
    result="$cmd"
  fi
  [ -z "$result" ] && result="$cmd"
  printf '%s\n' "$result"
}

# ── Branch helpers ───────────────────────────────────────────────────────────

current_branch() {
  git branch --show-current 2>/dev/null || echo ""
}

is_main_branch() {
  [ "$1" = "main" ] || [ "$1" = "master" ]
}

# ── Warning (non-blocking) ───────────────────────────────────────────────────
# emit_warn <message>
#   Writes warning to stderr. Does NOT output JSON to stdout.
#   Does NOT exit — caller continues or exits 0 as needed.
emit_warn() {
  echo "[GitHabits WARNING] $1" >&2
}

# ── TTY output (for native git hooks) ───────────────────────────────────────
# These functions output plain text to stderr for terminal users.
# No JSON — git hooks talk directly to the terminal, not to an agent.

# emit_block_tty <title> <message>
#   Prints a tutor-voice block message to stderr.
#   Caller is responsible for exiting with code 1 after calling this.
emit_block_tty() {
  local title="$1"
  local msg="$2"
  echo "" >&2
  echo "╔══════════════════════════════════════════════════════════════╗" >&2
  echo "║  GitHabits — $title" >&2
  echo "╚══════════════════════════════════════════════════════════════╝" >&2
  echo "" >&2
  echo "$msg" >&2
  echo "" >&2
}

# emit_hint_tty <message>
#   Prints a milestone hint to stderr.
emit_hint_tty() {
  local msg="$1"
  echo "" >&2
  echo "[GitHabits] $msg" >&2
  echo "" >&2
}

# ── Config reading ───────────────────────────────────────────────────────────

# read_config <key> <default>
#   Reads a value from githabits.conf (project-local first, then global).
#   Prints the value (or default if not found).
read_config() {
  local key="$1"
  local default_val="${2:-}"
  local val=""
  for conf in ".claude/githabits.conf" "$HOME/.claude/githabits.conf"; do
    if [ -f "$conf" ]; then
      val=$(grep -E "^${key}=" "$conf" 2>/dev/null | tail -1 | cut -d= -f2)
      break
    fi
  done
  printf '%s' "${val:-$default_val}"
}
