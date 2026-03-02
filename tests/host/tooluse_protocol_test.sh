#!/bin/bash
#
# tests/host/tooluse_protocol_test.sh
#
# Functional test for the native tool_use protocol (Phase 1 — CLI backend).
#
# Exercises the new 9P plumbing added for native tool_use support:
#   - /n/llm/{id}/tools (SessionToolsFile in session_tools.go)
#   - TOOL_RESULTS write path (parseToolResults in session_ask.go)
#   - agentlib buildtooldefs / initsessiontools / parsellmresponse
#
# Requirements:
#   - llm9p running on LLM9P_PORT (default 5640)
#   - Inferno emulator at $ROOT/emu/MacOSX/o.emu
#
# Usage:
#   ./tests/host/tooluse_protocol_test.sh            # port 5640
#   ./tests/host/tooluse_protocol_test.sh 5641       # custom port
#   ./tests/host/tooluse_protocol_test.sh -v         # verbose
#

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EMU="$ROOT/emu/MacOSX/o.emu"
LLM9P_PORT="${LLM9P_PORT:-5640}"
VERBOSE=0

# Parse flags
while getopts "vp:" opt; do
	case $opt in
		v) VERBOSE=1 ;;
		p) LLM9P_PORT="$OPTARG" ;;
		*) echo "Usage: $0 [-v] [-p port]"; exit 1 ;;
	esac
done
shift $((OPTIND-1))
if [ -n "$1" ] && echo "$1" | grep -qE '^[0-9]+$'; then
	LLM9P_PORT="$1"
fi

# Colour output (if terminal)
if [ -t 1 ]; then
	RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
	BOLD='\033[1m'; NC='\033[0m'
else
	RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

pass()  { echo -e "${GREEN}PASS${NC}: $1"; }
fail()  { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED+1)); }
skip()  { echo -e "${YELLOW}SKIP${NC}: $1"; SKIPPED=$((SKIPPED+1)); }
info()  { [ "$VERBOSE" -eq 1 ] && echo "  $1" || true; }

PASSED=0; FAILED=0; SKIPPED=0

# Helper: run a command inside a fresh emu instance with timeout.
# Captures output to a temp file and prints it in verbose mode.
run_emu() {
	local name="$1"; local tout="$2"; local cmds="$3"
	local logfile="/tmp/.tooluse-test-${name}.log"

	info "emu commands: $cmds"

	if timeout "$tout" "$EMU" -r"$ROOT" /dis/sh.dis -c "$cmds" \
		</dev/null >"$logfile" 2>/dev/null; then
		OUTPUT=$(cat "$logfile" 2>/dev/null)
		return 0
	else
		local rc=$?
		OUTPUT=$(cat "$logfile" 2>/dev/null)
		info "  exit code: $rc"
		return $rc
	fi
}

echo -e "${BOLD}Veltro tool_use protocol functional test${NC}"
echo "  llm9p port: $LLM9P_PORT"
echo ""

# ── Prerequisites ──────────────────────────────────────────────────

# Check llm9p is reachable
if ! nc -z localhost "$LLM9P_PORT" 2>/dev/null; then
	skip "llm9p not running on port $LLM9P_PORT (start with: llm9p -addr :${LLM9P_PORT} -backend cli)"
	echo ""
	echo "  Total: 0 passed, $FAILED failed, $SKIPPED skipped"
	exit 0
fi
info "llm9p is listening on port $LLM9P_PORT"

# Check emulator exists
if [ ! -x "$EMU" ]; then
	echo "ERROR: emulator not found at $EMU"
	exit 1
fi

# Build tooluse_test.dis if missing or stale
TESTDIS="$ROOT/dis/tests/tooluse_test.dis"
TESTB="$ROOT/tests/tooluse_test.b"
if [ ! -f "$TESTDIS" ] || [ "$TESTB" -nt "$TESTDIS" ]; then
	info "Building tooluse_test.dis..."
	PATH="$ROOT/MacOSX/arm64/bin:$PATH" \
		ROOT="$ROOT" \
		"$ROOT/MacOSX/arm64/bin/limbo" \
		-I"$ROOT/module" -I"$ROOT/appl/veltro" -gw \
		-o "$TESTDIS" "$TESTB" 2>&1 || {
		echo "ERROR: failed to build tooluse_test.dis"
		exit 1
	}
fi

# ── Test 1: Session creation via /n/llm/new ────────────────────────

echo "  Test 1: session creation via /n/llm/new"

CMDS1="mount -A tcp!127.0.0.1!${LLM9P_PORT} /n/llm; id = \`{cat /n/llm/new}; echo \$id"

if run_emu "session-create" 15 "$CMDS1"; then
	info "  Output: '$OUTPUT'"
	if echo "$OUTPUT" | grep -qE '^[0-9]+$'; then
		pass "Test 1: session ID is numeric ($OUTPUT)"
		PASSED=$((PASSED+1))
	elif [ -n "$OUTPUT" ]; then
		pass "Test 1: /n/llm/new returned: $OUTPUT"
		PASSED=$((PASSED+1))
	else
		fail "Test 1: /n/llm/new returned empty output"
	fi
else
	fail "Test 1: session creation failed (emu exit non-zero)"
fi

# ── Test 2: Tool definition write (session_tools.go) ───────────────

echo ""
echo "  Test 2: tool definition write to /n/llm/{id}/tools"

# Use the Limbo test for this — it calls agentlib->initsessiontools() which
# builds the JSON internally (avoids shell quoting issues with JSON)
CMDS2="mount -A tcp!127.0.0.1!${LLM9P_PORT} /n/llm; /tests/tooluse_test.dis"

if run_emu "tools-write" 30 "$CMDS2"; then
	info "  Output: $OUTPUT"
	if echo "$OUTPUT" | grep -qE 'passed'; then
		NPASS=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo 0)
		NSKIP=$(echo "$OUTPUT" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' || echo 0)
		NFAIL=$(echo "$OUTPUT" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo 0)
		if [ "${NFAIL:-0}" -eq 0 ]; then
			pass "Test 2: Limbo tooluse_test: ${NPASS} passed, ${NSKIP} skipped, 0 failed"
			PASSED=$((PASSED+1))
		else
			fail "Test 2: Limbo tooluse_test: ${NFAIL} failed"
		fi
	elif echo "$OUTPUT" | grep -q "PASS"; then
		pass "Test 2: Limbo tooluse_test passed"
		PASSED=$((PASSED+1))
	else
		fail "Test 2: unexpected output: $OUTPUT"
	fi
else
	fail "Test 2: Limbo tooluse_test exited non-zero"
	[ -n "$OUTPUT" ] && echo "    Output: $OUTPUT"
fi

# ── Test 3: TOOL_RESULTS parse via shell (session_ask.go) ──────────

echo ""
echo "  Test 3: TOOL_RESULTS write path (via Limbo test with /tool mounted)"

# The TOOL_RESULTS test in tooluse_test.b also calls the LLM first.
# Only run this if the user explicitly requested via -v (slow, requires claude CLI).
if [ "$VERBOSE" -eq 1 ]; then
	# Mount /tool as well to enable full toollist for BuildToolDefsAll
	# /tool requires tools9p to be running — skip if not available
	CMDS3="mount -A tcp!127.0.0.1!${LLM9P_PORT} /n/llm; /tests/tooluse_test.dis -v"
	if run_emu "toolresults" 120 "$CMDS3"; then
		info "  Output: $OUTPUT"
		pass "Test 3: tooluse_test with /n/llm (verbose, LLM calls)"
		PASSED=$((PASSED+1))
	else
		fail "Test 3: tooluse_test exited non-zero with LLM calls"
		[ -n "$OUTPUT" ] && echo "    Output: $OUTPUT"
	fi
else
	skip "Test 3: LLM-calling tests (run with -v to enable)"
fi

# ── Summary ────────────────────────────────────────────────────────

echo ""
echo -e "=== Results ==="
echo -e "  ${GREEN}Passed${NC}:  $PASSED"
echo -e "  ${RED}Failed${NC}:  $FAILED"
echo -e "  ${YELLOW}Skipped${NC}: $SKIPPED"
echo ""

if [ "$FAILED" -gt 0 ]; then
	exit 1
fi
exit 0
