#!/usr/bin/env bash
# Tests for GitHabits MCP server
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$SCRIPT_DIR/../mcp/githabits-mcp-server"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
RESULTS_FILE="$TMPDIR/results.log"
touch "$RESULTS_FILE"
export RESULTS_FILE

pass() { echo "  ✓ $1"; echo "PASS" >> "$RESULTS_FILE"; }
fail() { echo "  ✗ $1"; echo "FAIL" >> "$RESULTS_FILE"; }

# Helper: send a JSON-RPC message and capture stdout (stderr suppressed)
call_server() {
  echo "$1" | python3 "$SERVER" 2>/dev/null
}

# Helper: extract the text content from a tools/call response
extract_text() {
  python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
content = data.get('result', {}).get('content', [{}])
if content:
    print(content[0].get('text', ''))
"
}

# Helper: parse JSON field from text content
extract_field() {
  local field="$1"
  python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
print(data.get('$field', ''))
"
}

# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Protocol basics ==="

# T1: Initialize handshake
RESP=$(call_server '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}')
if echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['result']['serverInfo']['name']=='githabits'" 2>/dev/null; then
  pass "T1: Initialize returns server info"
else
  fail "T1: Initialize handshake failed"
fi

# T2: Protocol version
if echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['result']['protocolVersion']=='2024-11-05'" 2>/dev/null; then
  pass "T2: Protocol version is 2024-11-05"
else
  fail "T2: Wrong protocol version"
fi

# T3: Capabilities include tools and resources
if echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); r=d['result']['capabilities']; assert 'tools' in r and 'resources' in r" 2>/dev/null; then
  pass "T3: Capabilities include tools and resources"
else
  fail "T3: Missing capabilities"
fi

# T4: Notifications don't produce output
RESP=$(call_server '{"jsonrpc":"2.0","method":"notifications/initialized"}')
if [ -z "$RESP" ]; then
  pass "T4: Notification produces no output"
else
  fail "T4: Notification produced output: $RESP"
fi

# T5: Unknown method returns error
RESP=$(call_server '{"jsonrpc":"2.0","method":"bogus/method","id":99,"params":{}}')
if echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['error']['code']==-32601" 2>/dev/null; then
  pass "T5: Unknown method returns -32601 error"
else
  fail "T5: Wrong error for unknown method"
fi

# T6: Invalid JSON returns parse error
RESP=$(call_server 'not json at all')
if echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['error']['code']==-32700" 2>/dev/null; then
  pass "T6: Invalid JSON returns -32700 parse error"
else
  fail "T6: Wrong error for invalid JSON"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== tools/list ==="

RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/list","id":10,"params":{}}')

# T7: Returns 3 tools
TOOL_COUNT=$(echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(len(d['result']['tools']))")
if [ "$TOOL_COUNT" = "3" ]; then
  pass "T7: tools/list returns 3 tools"
else
  fail "T7: Expected 3 tools, got $TOOL_COUNT"
fi

# T8: Tool names are correct
TOOL_NAMES=$(echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(','.join(sorted(t['name'] for t in d['result']['tools'])))")
if [ "$TOOL_NAMES" = "explain_command,suggest_next_step,validate_git_operation" ]; then
  pass "T8: Tool names are correct"
else
  fail "T8: Wrong tool names: $TOOL_NAMES"
fi

# T9: Each tool has inputSchema
SCHEMAS=$(echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(all('inputSchema' in t for t in d['result']['tools']))")
if [ "$SCHEMAS" = "True" ]; then
  pass "T9: All tools have inputSchema"
else
  fail "T9: Missing inputSchema on some tools"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== validate_git_operation ==="

# Run tests inside a git repo on main branch
(
  cd "$TMPDIR"
  mkdir -p test-repo && cd test-repo
  git init -b main >/dev/null 2>&1
  git commit --allow-empty -m "init" >/dev/null 2>&1

  # T10: Commit on main → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":20,"params":{"name":"validate_git_operation","arguments":{"command":"git commit -m fix"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T10: Commit on main is blocked"
  else
    fail "T10: Commit on main was allowed"
  fi

  # T11: Push to main → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":21,"params":{"name":"validate_git_operation","arguments":{"command":"git push origin main"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T11: Push to main is blocked"
  else
    fail "T11: Push to main was allowed"
  fi

  # T12: git reset --hard → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":22,"params":{"name":"validate_git_operation","arguments":{"command":"git reset --hard HEAD"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T12: git reset --hard is blocked"
  else
    fail "T12: git reset --hard was allowed"
  fi

  # T13: git clean -f → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":23,"params":{"name":"validate_git_operation","arguments":{"command":"git clean -fd"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T13: git clean -f is blocked"
  else
    fail "T13: git clean -f was allowed"
  fi

  # T14: git clean -n (dry run) → allowed
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":24,"params":{"name":"validate_git_operation","arguments":{"command":"git clean -n"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "True" ]; then
    pass "T14: git clean -n (dry run) is allowed"
  else
    fail "T14: git clean -n was blocked"
  fi

  # T15: Force push to main → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":25,"params":{"name":"validate_git_operation","arguments":{"command":"git push --force origin main"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T15: Force push to main is blocked"
  else
    fail "T15: Force push to main was allowed"
  fi

  # T16: Merge into main → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":26,"params":{"name":"validate_git_operation","arguments":{"command":"git merge feature/x"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T16: Merge into main is blocked"
  else
    fail "T16: Merge into main was allowed"
  fi

  # T17: Push --all → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":27,"params":{"name":"validate_git_operation","arguments":{"command":"git push --all"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T17: git push --all is blocked"
  else
    fail "T17: git push --all was allowed"
  fi

  # T18: Delete remote main → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":28,"params":{"name":"validate_git_operation","arguments":{"command":"git push origin --delete main"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T18: Delete remote main is blocked"
  else
    fail "T18: Delete remote main was allowed"
  fi

  # T19: Safe operation on feature branch → allowed
  git checkout -b feature/test >/dev/null 2>&1
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":29,"params":{"name":"validate_git_operation","arguments":{"command":"git commit -m fix"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "True" ]; then
    pass "T19: Commit on feature branch is allowed"
  else
    fail "T19: Commit on feature branch was blocked"
  fi

  # T20: Push feature branch → allowed
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":30,"params":{"name":"validate_git_operation","arguments":{"command":"git push origin feature/test"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "True" ]; then
    pass "T20: Push feature branch is allowed"
  else
    fail "T20: Push feature branch was blocked"
  fi

  # T21: GITHABITS_ALLOW_MAIN=1 bypasses all checks
  git checkout main >/dev/null 2>&1
  RESP=$(GITHABITS_ALLOW_MAIN=1 call_server '{"jsonrpc":"2.0","method":"tools/call","id":31,"params":{"name":"validate_git_operation","arguments":{"command":"git commit -m fix"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "True" ]; then
    pass "T21: GITHABITS_ALLOW_MAIN=1 bypasses checks"
  else
    fail "T21: GITHABITS_ALLOW_MAIN override failed"
  fi

  # T22: Chained command with dangerous subcommand → blocked
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":32,"params":{"name":"validate_git_operation","arguments":{"command":"echo done && git push origin main"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "False" ]; then
    pass "T22: Chained command with push to main is blocked"
  else
    fail "T22: Chained command was allowed"
  fi

  # T23: Non-git command → allowed
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":33,"params":{"name":"validate_git_operation","arguments":{"command":"npm install"}}}')
  ALLOWED=$(echo "$RESP" | extract_text | extract_field allowed)
  if [ "$ALLOWED" = "True" ]; then
    pass "T23: Non-git command is allowed"
  else
    fail "T23: Non-git command was blocked"
  fi

  # T24: Block response includes reason and suggestion
  RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":34,"params":{"name":"validate_git_operation","arguments":{"command":"git commit -m fix"}}}')
  TEXT=$(echo "$RESP" | extract_text)
  HAS_REASON=$(echo "$TEXT" | extract_field reason)
  HAS_SUGGESTION=$(echo "$TEXT" | extract_field suggestion)
  if [ -n "$HAS_REASON" ] && [ -n "$HAS_SUGGESTION" ]; then
    pass "T24: Block includes reason and suggestion"
  else
    fail "T24: Block missing reason or suggestion"
  fi
)

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== suggest_next_step ==="

# T25: new-branch event
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":40,"params":{"name":"suggest_next_step","arguments":{"event":"new-branch","branch":"feature/login"}}}')
HINT=$(echo "$RESP" | extract_text | extract_field hint)
if echo "$HINT" | grep -qi "branch"; then
  pass "T25: new-branch hint mentions branch"
else
  fail "T25: new-branch hint missing: $HINT"
fi

# T26: commit event includes push command
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":41,"params":{"name":"suggest_next_step","arguments":{"event":"commit","branch":"feature/login"}}}')
NEXT=$(echo "$RESP" | extract_text | extract_field next_command)
if echo "$NEXT" | grep -q "git push origin feature/login"; then
  pass "T26: commit suggests push with branch name"
else
  fail "T26: commit next_command wrong: $NEXT"
fi

# T27: push event suggests PR
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":42,"params":{"name":"suggest_next_step","arguments":{"event":"push","branch":"feature/login"}}}')
HINT=$(echo "$RESP" | extract_text | extract_field hint)
if echo "$HINT" | grep -qi "pull request"; then
  pass "T27: push hint suggests pull request"
else
  fail "T27: push hint missing PR suggestion"
fi

# T28: pull event suggests feature branch
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":43,"params":{"name":"suggest_next_step","arguments":{"event":"pull","branch":"main"}}}')
NEXT=$(echo "$RESP" | extract_text | extract_field next_command)
if echo "$NEXT" | grep -q "checkout -b"; then
  pass "T28: pull suggests creating feature branch"
else
  fail "T28: pull next_command wrong: $NEXT"
fi

# T29: Unknown event returns empty hint
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":44,"params":{"name":"suggest_next_step","arguments":{"event":"unknown-thing","branch":"main"}}}')
HINT=$(echo "$RESP" | extract_text | extract_field hint)
if [ -z "$HINT" ]; then
  pass "T29: Unknown event returns empty hint"
else
  fail "T29: Unknown event returned hint: $HINT"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== explain_command ==="

# T30: Simple command explanation
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":50,"params":{"name":"explain_command","arguments":{"command":"git log --oneline -5"}}}')
EXPLANATION=$(echo "$RESP" | extract_text | extract_field explanation)
if echo "$EXPLANATION" | grep -q "git log --oneline -5"; then
  pass "T30: Explanation includes the command"
else
  fail "T30: Explanation missing command"
fi

# T31: Chained command explanation mentions parts
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":51,"params":{"name":"explain_command","arguments":{"command":"git add . && git commit -m fix"}}}')
EXPLANATION=$(echo "$RESP" | extract_text | extract_field explanation)
if echo "$EXPLANATION" | grep -q "chained" && echo "$EXPLANATION" | grep -q "git add" && echo "$EXPLANATION" | grep -q "git commit"; then
  pass "T31: Chained command explanation mentions both parts"
else
  fail "T31: Chained command explanation incomplete"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== resources ==="

# T32: resources/list returns 2 resources
RESP=$(call_server '{"jsonrpc":"2.0","method":"resources/list","id":60,"params":{}}')
COUNT=$(echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(len(d['result']['resources']))")
if [ "$COUNT" = "2" ]; then
  pass "T32: resources/list returns 2 resources"
else
  fail "T32: Expected 2 resources, got $COUNT"
fi

# T33: githabits://status returns branch info
RESP=$(call_server '{"jsonrpc":"2.0","method":"resources/read","id":61,"params":{"uri":"githabits://status"}}')
HAS_BRANCH=$(echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); t=d['result']['contents'][0]['text']; s=json.loads(t); print('branch' in s)")
if [ "$HAS_BRANCH" = "True" ]; then
  pass "T33: githabits://status includes branch"
else
  fail "T33: status resource missing branch"
fi

# T34: githabits://config returns settings
RESP=$(call_server '{"jsonrpc":"2.0","method":"resources/read","id":62,"params":{"uri":"githabits://config"}}')
HAS_SCOPE=$(echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); t=d['result']['contents'][0]['text']; s=json.loads(t); print('EXPLAIN_SCOPE' in s)")
if [ "$HAS_SCOPE" = "True" ]; then
  pass "T34: githabits://config includes EXPLAIN_SCOPE"
else
  fail "T34: config resource missing EXPLAIN_SCOPE"
fi

# T35: Unknown resource returns error
RESP=$(call_server '{"jsonrpc":"2.0","method":"resources/read","id":63,"params":{"uri":"githabits://bogus"}}')
if echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'error' in d" 2>/dev/null; then
  pass "T35: Unknown resource returns error"
else
  fail "T35: Unknown resource didn't error"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Error handling ==="

# T36: Missing required argument
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":70,"params":{"name":"validate_git_operation","arguments":{}}}')
if echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['error']['code']==-32602" 2>/dev/null; then
  pass "T36: Missing argument returns -32602"
else
  fail "T36: Wrong error for missing argument"
fi

# T37: Unknown tool returns error
RESP=$(call_server '{"jsonrpc":"2.0","method":"tools/call","id":71,"params":{"name":"nonexistent_tool","arguments":{}}}')
if echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['error']['code']==-32601" 2>/dev/null; then
  pass "T37: Unknown tool returns -32601"
else
  fail "T37: Wrong error for unknown tool"
fi

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
