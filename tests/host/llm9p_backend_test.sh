#!/bin/sh
# Regression test: llm9p must run with -backend api for tool_use to work.
#
# Background (2026-03-08):
#   The feat(bundle) commit switched llm9p from the launchd daemon
#   (~/.local/bin/llm9p -backend api) to the bundled binary with -backend cli.
#   The CLI backend uses the Claude Code CLI, which has its OWN built-in tool
#   set (Bash, Read, Write, etc.). When Veltro's custom tools (present, exec,
#   list, etc.) are sent as tool schemas to the CLI backend, the model confuses
#   them with Claude Code tools and refuses to call them — responding with text
#   explanations instead of tool_use blocks.
#
#   The API backend sends tool schemas directly to the Anthropic API, which
#   supports proper custom tool_use and returns STOP:/TOOL: formatted responses
#   that agentlib.b can parse and dispatch.
#
# This test verifies:
#   1. ANTHROPIC_API_KEY is discoverable (env or launchd plist)
#   2. start-llm9p.sh selects -backend api when key is available
#   3. If llm9p is running, it is using -backend api (not cli)

PLIST="$HOME/Library/LaunchAgents/com.nervsystems.llm9p.plist"
PASS=0
FAIL=0

ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP: $1"; }

# Test 1: ANTHROPIC_API_KEY must be obtainable
key="$ANTHROPIC_API_KEY"
if [ -z "$key" ] && [ -f "$PLIST" ]; then
    key=$(plutil -extract EnvironmentVariables.ANTHROPIC_API_KEY raw "$PLIST" 2>/dev/null)
fi
if [ -n "$key" ] && [ ${#key} -gt 20 ]; then
    ok "ANTHROPIC_API_KEY is available (${#key} chars)"
else
    fail "ANTHROPIC_API_KEY not found in env or $PLIST — API backend cannot start; tool_use will not work"
fi

# Test 2: start-llm9p.sh must select api backend when key is available
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/lib/sh/start-llm9p.sh"
if [ ! -f "$SCRIPT" ]; then
    fail "start-llm9p.sh not found at $SCRIPT"
else
    if grep -q 'BACKEND="api"' "$SCRIPT" && grep -q 'plutil.*ANTHROPIC_API_KEY' "$SCRIPT"; then
        ok "start-llm9p.sh contains API backend selection logic"
    else
        fail "start-llm9p.sh does not select api backend — edit it to use -backend api when ANTHROPIC_API_KEY is available"
    fi
fi

# Test 3: InferNode.app launcher must select api backend when key is available
LAUNCHER="$(cd "$(dirname "$0")/../.." && pwd)/MacOSX/InferNode.app/Contents/MacOS/InferNode"
if [ ! -f "$LAUNCHER" ]; then
    skip "InferNode launcher not found (non-macOS build)"
else
    if grep -q 'BACKEND="api"' "$LAUNCHER" && grep -q 'plutil.*ANTHROPIC_API_KEY' "$LAUNCHER"; then
        ok "InferNode launcher contains API backend selection logic"
    else
        fail "InferNode launcher hardcodes -backend cli — update it to prefer api backend"
    fi
fi

# Test 4: If llm9p is running on :5640, verify it is using api backend
if pgrep -qf "llm9p.*-addr :5640" 2>/dev/null; then
    if pgrep -qf "llm9p.*-backend api.*-addr :5640" 2>/dev/null || \
       pgrep -qf "llm9p.*-addr :5640.*-backend api" 2>/dev/null; then
        ok "Running llm9p uses -backend api"
    else
        running=$(pgrep -fl "llm9p.*5640" 2>/dev/null)
        fail "Running llm9p does NOT use -backend api: $running"
    fi
else
    skip "llm9p not running on :5640 (start it first to test)"
fi

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
