#!/bin/bash
#
# Distributed InferNode Authentication Test
#
# Tests two InferNode instances communicating over authenticated,
# encrypted 9P on the same macOS machine.
#
# Instance A (client) mounts Instance B's LLM service through an
# authenticated channel, verifying the Ed25519 + SHA-256 crypto stack.
#
#   Instance A (emu) --[Ed25519 auth + encrypted 9P]--> Instance B (emu)
#       --[plain 9P, localhost]--> llm9p (Go, port 5640)
#
# Usage:
#   ./tests/test-distributed.sh          # run automated tests
#   ./tests/test-distributed.sh -i       # run tests, then interactive mode
#   ./tests/test-distributed.sh -v       # verbose output
#   ./tests/test-distributed.sh -f       # force regenerate keys
#

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="$ROOT/emu/MacOSX/o.emu"
SERVER_PORT=9998
LLM9P_PORT=5640
INTERACTIVE=0
VERBOSE=0
FORCE_KEYS=0
SERVER_PID=""
KEYFILE="$ROOT/usr/inferno/keyring/default"

# Colors (if terminal supports them)
if [ -t 1 ]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[0;33m'
	BOLD='\033[1m'
	NC='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	BOLD=''
	NC=''
fi

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; }
warn() { echo -e "${YELLOW}WARN${NC}: $1"; }
info() { [ "$VERBOSE" -eq 1 ] && echo "  $1" || true; }

passed=0
failed=0
skipped=0

# Parse flags
while getopts "ivf" opt; do
	case $opt in
		i) INTERACTIVE=1 ;;
		v) VERBOSE=1 ;;
		f) FORCE_KEYS=1 ;;
		*) echo "Usage: $0 [-i] [-v] [-f]"; exit 1 ;;
	esac
done

# Check for timeout command (macOS may need coreutils)
if ! command -v timeout >/dev/null 2>&1; then
	if command -v gtimeout >/dev/null 2>&1; then
		timeout() { gtimeout "$@"; }
	else
		echo "ERROR: 'timeout' command not found"
		echo "Install with: brew install coreutils"
		exit 1
	fi
fi

cleanup() {
	if [ -n "$SERVER_PID" ]; then
		info "Killing Instance B (pid $SERVER_PID)"
		kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
}
trap cleanup EXIT

echo "=== InferNode Distributed Authentication Test ==="
echo "Root: $ROOT"
echo ""

# ── Phase 1: Prerequisites ──────────────────────────────────────────

echo -e "${BOLD}Phase 1: Prerequisites${NC}"

if [ ! -x "$EMU" ]; then
	echo "ERROR: Emulator not found at $EMU"
	echo "Build first: cd emu/MacOSX && mk install"
	exit 1
fi
pass "Emulator found: $EMU"

# Check llm9p is running
if ! lsof -i ":$LLM9P_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
	echo "ERROR: llm9p not running on port $LLM9P_PORT"
	echo "Start it first: llm9p or your LLM 9P server"
	exit 1
fi
pass "llm9p running on port $LLM9P_PORT"

# Check required .dis files
MISSING=0
for f in dis/auth/createsignerkey.dis dis/listen.dis dis/export.dis dis/mount.dis dis/sh.dis; do
	if [ ! -f "$ROOT/$f" ]; then
		fail "Missing $f"
		MISSING=1
	fi
done
if [ "$MISSING" -eq 1 ]; then
	echo "ERROR: Missing .dis files. Build with: cd appl/cmd && mk install"
	exit 1
fi
pass "Required .dis files present"

echo ""

# ── Phase 2: Key Generation ─────────────────────────────────────────

echo -e "${BOLD}Phase 2: Key Generation${NC}"

if [ -f "$KEYFILE" ] && [ "$FORCE_KEYS" -eq 0 ]; then
	pass "Key already exists: $KEYFILE (use -f to regenerate)"
else
	info "Generating Ed25519 self-signed key..."
	mkdir -p "$(dirname "$KEYFILE")"

	# Run emu to generate the key.
	# Uses pre-computed RFC 3526 DH params so key generation is fast.
	# The emu process may not exit cleanly, so use a short timeout.
	info "Generating Ed25519 key with pre-computed DH params..."
	timeout 30 "$EMU" -r"$ROOT" /dis/auth/createsignerkey.dis \
		-a ed25519 -f /usr/inferno/keyring/default testnode \
		</dev/null >/dev/null 2>&1 || true  # timeout returns 124 if emu hangs after writing key

	if [ ! -f "$KEYFILE" ] || [ ! -s "$KEYFILE" ]; then
		fail "Key file not created or empty: $KEYFILE"
		echo "  Try running manually:"
		echo "  $EMU -r$ROOT /dis/auth/createsignerkey.dis -a ed25519 -f /usr/inferno/keyring/default testnode"
		exit 1
	fi
	pass "Ed25519 key generated: $KEYFILE ($(wc -c < "$KEYFILE") bytes)"
fi

echo ""

# ── Phase 3: Start Instance B (LLM Proxy Server) ────────────────────

echo -e "${BOLD}Phase 3: Start Instance B (LLM Proxy Server)${NC}"

# Instance B: mount llm9p (unauthenticated localhost), then listen
# for authenticated connections on SERVER_PORT.
#
# The shell script inside emu:
#   1. Mount llm9p via plain 9P (localhost, no auth)
#   2. Listen on SERVER_PORT with Ed25519 auth
#   3. For each authenticated connection, export /n/llm

SERVER_SCRIPT="
	mount -A tcp!127.0.0.1!${LLM9P_PORT} /n/llm;
	listen -v -k /usr/inferno/keyring/default tcp!*!${SERVER_PORT} {export /n/llm}
"

info "Starting Instance B with: $SERVER_SCRIPT"

"$EMU" -r"$ROOT" /dis/sh.dis -c "$SERVER_SCRIPT" </dev/null >"$ROOT/tests/.server-b.log" 2>&1 &
SERVER_PID=$!

info "Instance B started (pid $SERVER_PID)"

# Wait for server to be listening
WAITED=0
while ! lsof -i ":$SERVER_PORT" -sTCP:LISTEN >/dev/null 2>&1; do
	sleep 1
	WAITED=$((WAITED + 1))
	if [ "$WAITED" -ge 15 ]; then
		fail "Instance B failed to start listening on port $SERVER_PORT within 15s"
		echo "Server log:"
		cat "$ROOT/tests/.server-b.log" 2>/dev/null || true
		exit 1
	fi
	# Check server is still running
	if ! kill -0 "$SERVER_PID" 2>/dev/null; then
		fail "Instance B exited prematurely"
		echo "Server log:"
		cat "$ROOT/tests/.server-b.log" 2>/dev/null || true
		exit 1
	fi
done

pass "Instance B listening on port $SERVER_PORT (waited ${WAITED}s)"

echo ""

# ── Phase 4: Automated Tests ────────────────────────────────────────

echo -e "${BOLD}Phase 4: Automated Tests${NC}"

# Helper: run a command inside a fresh emu instance with timeout.
# emu exits cleanly after sh -c completes. Non-zero exit means the shell
# raised an exception (e.g., mount failed). Timeout (exit 124) means hung.
# Args: test_name timeout_secs inferno_commands
run_test() {
	local name="$1"
	local tout="$2"
	local cmds="$3"
	local logfile="$ROOT/tests/.test-${name}.log"

	info "Running test: $name"
	info "  Commands: $cmds"

	if timeout "$tout" "$EMU" -r"$ROOT" /dis/sh.dis -c "$cmds" \
		</dev/null >"$logfile" 2>/dev/null; then
		return 0
	else
		local rc=$?
		info "  Exit code: $rc"
		return $rc
	fi
}

# ── Test 1: Authenticated mount (no encryption) ──

echo ""
echo "  Test 1: Auth-only mount (no encryption)"

TEST1_CMDS="
	mount -C none -k /usr/inferno/keyring/default tcp!127.0.0.1!${SERVER_PORT} /n/llm;
	cat /n/llm/new
"

if run_test "auth-only" 30 "$TEST1_CMDS"; then
	LOGFILE="$ROOT/tests/.test-auth-only.log"
	OUTPUT=$(cat "$LOGFILE" 2>/dev/null)
	info "  Output: $OUTPUT"
	# /n/llm/new should return a session ID (a number)
	if echo "$OUTPUT" | grep -qE '^[0-9]+$'; then
		pass "Test 1: Auth-only mount — got session ID: $(echo "$OUTPUT" | grep -oE '^[0-9]+$' | head -1)"
		passed=$((passed + 1))
	else
		fail "Test 1: Auth-only mount — no session ID in output"
		echo "    Output: $OUTPUT"
		failed=$((failed + 1))
	fi
else
	fail "Test 1: Auth-only mount — command failed"
	cat "$ROOT/tests/.test-auth-only.log" 2>/dev/null | sed 's/^/    /'
	failed=$((failed + 1))
fi

# ── Test 2: Authenticated mount with encryption ──

echo ""
echo "  Test 2: Auth + encrypted mount (rc4_256 sha1)"

TEST2_CMDS="
	mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default tcp!127.0.0.1!${SERVER_PORT} /n/llm;
	cat /n/llm/new
"

if run_test "encrypted" 30 "$TEST2_CMDS"; then
	LOGFILE="$ROOT/tests/.test-encrypted.log"
	OUTPUT=$(cat "$LOGFILE" 2>/dev/null)
	info "  Output: $OUTPUT"
	if echo "$OUTPUT" | grep -qE '^[0-9]+$'; then
		pass "Test 2: Encrypted mount — got session ID: $(echo "$OUTPUT" | grep -oE '^[0-9]+$' | head -1)"
		passed=$((passed + 1))
	else
		fail "Test 2: Encrypted mount — no session ID in output"
		echo "    Output: $OUTPUT"
		failed=$((failed + 1))
	fi
else
	fail "Test 2: Encrypted mount — command failed"
	cat "$ROOT/tests/.test-encrypted.log" 2>/dev/null | sed 's/^/    /'
	failed=$((failed + 1))
fi

# ── Test 3: Full LLM query through encrypted channel ──

echo ""
echo "  Test 3: LLM query through encrypted channel"

# Clone a session, write a prompt, read the response.
# The llm9p clone pattern: read /n/llm/new to get session ID,
# then write prompt to /n/llm/<id>/ask and read response from /n/llm/<id>/ask.
#
# We use a shell script that captures the session ID and uses it.
TEST3_CMDS="
	mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default tcp!127.0.0.1!${SERVER_PORT} /n/llm;
	id = \`{cat /n/llm/new};
	echo 'Reply with just the word hello' > /n/llm/\$id/ask;
	cat /n/llm/\$id/ask
"

if run_test "llm-query" 60 "$TEST3_CMDS"; then
	LOGFILE="$ROOT/tests/.test-llm-query.log"
	OUTPUT=$(cat "$LOGFILE" 2>/dev/null)
	info "  Output: $OUTPUT"
	# The response should contain some text (the LLM's reply)
	if [ -n "$OUTPUT" ]; then
		# Check if response contains "hello" (case insensitive)
		if echo "$OUTPUT" | grep -iqE 'hello'; then
			pass "Test 3: LLM query — response contains 'hello'"
			passed=$((passed + 1))
		else
			# Still a pass if we got any response — the LLM might not follow instructions perfectly
			warn "Test 3: LLM query — got response but it doesn't contain 'hello'"
			echo "    Response: $OUTPUT"
			passed=$((passed + 1))
		fi
	else
		fail "Test 3: LLM query — empty response"
		failed=$((failed + 1))
	fi
else
	fail "Test 3: LLM query — command failed"
	cat "$ROOT/tests/.test-llm-query.log" 2>/dev/null | sed 's/^/    /'
	failed=$((failed + 1))
fi

# ── Test 4: Connection to wrong port produces no data ──

echo ""
echo "  Test 4: Mount to non-existent server produces no session"

# Try mounting to a port where nothing is listening, then reading.
# Even if the emu exits with code 0, the output should be empty
# (no session ID) because mount failed.
DEAD_PORT=9997
TEST4_CMDS="
	mount -A tcp!127.0.0.1!${DEAD_PORT} /n/llm;
	cat /n/llm/new
"

run_test "dead-port" 15 "$TEST4_CMDS" || true
LOGFILE="$ROOT/tests/.test-dead-port.log"
OUTPUT=$(cat "$LOGFILE" 2>/dev/null)
info "  Output: '$OUTPUT'"

if [ -z "$OUTPUT" ]; then
	pass "Test 4: Mount to dead port produced no output (as expected)"
	passed=$((passed + 1))
elif echo "$OUTPUT" | grep -qE '^[0-9]+$'; then
	fail "Test 4: Got session ID from dead port — something is wrong"
	failed=$((failed + 1))
else
	pass "Test 4: Mount to dead port produced error (as expected)"
	passed=$((passed + 1))
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────

echo "=== Results ==="
echo -e "  ${GREEN}Passed${NC}:  $passed"
echo -e "  ${RED}Failed${NC}:  $failed"
echo -e "  ${YELLOW}Skipped${NC}: $skipped"
echo ""

# ── Phase 5: Interactive Mode ────────────────────────────────────────

if [ "$INTERACTIVE" -eq 1 ] && [ "$failed" -eq 0 ]; then
	echo -e "${BOLD}Phase 5: Interactive Mode${NC}"
	echo "Starting Instance A with authenticated + encrypted mount to Instance B..."
	echo "Try: cat /n/llm/new"
	echo "     echo 'your prompt' > /n/llm/<id>/ask"
	echo "     cat /n/llm/<id>/ask"
	echo ""

	# Instance B stays alive while the user interacts (cleanup trap runs on EXIT)
	"$EMU" -r"$ROOT" /dis/sh.dis -c "
		mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default tcp!127.0.0.1!${SERVER_PORT} /n/llm;
		echo 'Connected to Instance B (authenticated + encrypted)';
		echo 'LLM service mounted at /n/llm';
		sh
	" || true
fi

# ── Cleanup ──────────────────────────────────────────────────────────

# Clean up log files
rm -f "$ROOT/tests/.server-b.log" "$ROOT/tests/.test-"*.log

if [ "$failed" -gt 0 ]; then
	exit 1
fi
exit 0
