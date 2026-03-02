#!/bin/bash
#
# Cross-Host InferNode Authentication Test
#
# Tests two InferNode instances on different hosts communicating over
# authenticated, encrypted 9P through a ZeroTier VPN.
#
# The local machine (macOS) acts as the client.  A remote machine
# (Linux ARM64, e.g. Jetson) acts as the server, exporting its root
# namespace over Ed25519-authenticated 9P.
#
#   Local (macOS)                        Remote (Linux ARM64)
#   ┌──────────┐    ZeroTier VPN    ┌──────────────────┐
#   │ emu      │ ──[Ed25519 auth]──>│ emu              │
#   │ (client) │   [encrypted 9P]   │ listen + export /│
#   └──────────┘                    └──────────────────┘
#
# Prerequisites:
#   - SSH access to the remote host (e.g. ssh hephaestus)
#   - ZeroTier or other network connectivity between hosts
#   - InferNode checked out and built on both machines
#   - Shared Ed25519 key (copied automatically if missing)
#
# Usage:
#   ./tests/test-cross-host.sh                         # run with defaults
#   ./tests/test-cross-host.sh -r hephaestus           # specify remote host
#   ./tests/test-cross-host.sh -a 10.243.169.78        # specify remote IP
#   ./tests/test-cross-host.sh -p 9999                 # specify port
#   ./tests/test-cross-host.sh -v                      # verbose output
#   ./tests/test-cross-host.sh -f                      # force regenerate keys
#   ./tests/test-cross-host.sh -i                      # interactive mode after tests
#

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="$ROOT/emu/MacOSX/o.emu"
SERVER_PORT=9999
REMOTE_HOST="hephaestus"
REMOTE_ADDR=""
REMOTE_ROOT='~/github.com/NERVsystems/infernode'
REMOTE_EMU_REL="emu/Linux/o.emu"
KEYFILE="$ROOT/usr/inferno/keyring/default"
INTERACTIVE=0
VERBOSE=0
FORCE_KEYS=0

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
while getopts "r:a:p:ivf" opt; do
	case $opt in
		r) REMOTE_HOST="$OPTARG" ;;
		a) REMOTE_ADDR="$OPTARG" ;;
		p) SERVER_PORT="$OPTARG" ;;
		i) INTERACTIVE=1 ;;
		v) VERBOSE=1 ;;
		f) FORCE_KEYS=1 ;;
		*) echo "Usage: $0 [-r remote_host] [-a remote_ip] [-p port] [-i] [-v] [-f]"; exit 1 ;;
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

# Helper: run a command inside a fresh local emu instance with timeout.
# Uses a temp script to avoid shell quoting issues with ! characters.
run_emu() {
	local tout="$1"
	local cmds="$2"
	local tmpscript
	tmpscript=$(mktemp /tmp/infernode-test-XXXXXX.sh)
	cat > "$tmpscript" << EMUSCRIPT
#!/bin/bash
cd "$ROOT"
# Use double quotes so inner single quotes (e.g. 'rc4_256 sha1') pass through
exec ./emu/MacOSX/o.emu -r . /dis/sh.dis -c "$cmds"
EMUSCRIPT
	chmod +x "$tmpscript"
	timeout "$tout" bash "$tmpscript" 2>&1
	local rc=$?
	rm -f "$tmpscript"
	return $rc
}

# Helper: run a command on the remote host via SSH.
# Uses scp'd scripts to avoid quoting issues with cloudflared proxy.
run_remote() {
	local cmds="$1"
	ssh "$REMOTE_HOST" "$cmds"
}

cleanup() {
	info "Stopping remote server..."
	ssh "$REMOTE_HOST" 'tmux kill-session -t infernode-test 2>/dev/null' || true
}
trap cleanup EXIT

echo "=== InferNode Cross-Host Authentication Test ==="
echo "Root:        $ROOT"
echo "Remote host: $REMOTE_HOST"
echo "Server port: $SERVER_PORT"
echo ""

# ── Phase 1: Prerequisites ──────────────────────────────────────────

echo -e "${BOLD}Phase 1: Prerequisites${NC}"

if [ ! -x "$EMU" ]; then
	echo "ERROR: Local emulator not found at $EMU"
	exit 1
fi
pass "Local emulator found"

# Check SSH connectivity
if ! ssh -o ConnectTimeout=10 "$REMOTE_HOST" 'echo ok' >/dev/null 2>&1; then
	echo "ERROR: Cannot SSH to $REMOTE_HOST"
	echo "Check: ssh $REMOTE_HOST"
	exit 1
fi
pass "SSH to $REMOTE_HOST works"

# Discover remote IP if not specified
if [ -z "$REMOTE_ADDR" ]; then
	# Try to get ZeroTier address (10.243.x.x range)
	REMOTE_ADDR=$(ssh "$REMOTE_HOST" "ip addr show 2>/dev/null | grep 'inet 10\\.243\\.' | awk '{print \$2}' | cut -d/ -f1 | head -1" 2>/dev/null)
	if [ -z "$REMOTE_ADDR" ]; then
		# Fall back to hostname resolution
		REMOTE_ADDR=$(ssh "$REMOTE_HOST" 'hostname -I 2>/dev/null | tr " " "\n" | head -1' 2>/dev/null)
	fi
	if [ -z "$REMOTE_ADDR" ]; then
		echo "ERROR: Could not determine remote IP address"
		echo "Specify with: $0 -a <ip>"
		exit 1
	fi
fi
pass "Remote address: $REMOTE_ADDR"

# Check remote emulator
if ! ssh "$REMOTE_HOST" "test -x $REMOTE_ROOT/$REMOTE_EMU_REL" 2>/dev/null; then
	echo "ERROR: Remote emulator not found at $REMOTE_ROOT/$REMOTE_EMU_REL"
	echo "Build on remote: cd $REMOTE_ROOT && ./build-linux-arm64.sh"
	exit 1
fi
pass "Remote emulator found"

# Verify network connectivity
# macOS ping -W is in milliseconds; use 5000ms to handle high-latency links
LATENCY=$(ping -c 1 -W 5000 "$REMOTE_ADDR" 2>/dev/null | grep 'time=' | sed 's/.*time=\([^ ]*\).*/\1/')
if [ -z "$LATENCY" ]; then
	echo "ERROR: Cannot ping $REMOTE_ADDR"
	echo "Check ZeroTier connectivity"
	exit 1
fi
pass "Network latency to $REMOTE_ADDR: ${LATENCY}ms"

# Check port is free on remote
if ssh "$REMOTE_HOST" "ss -tlnp sport = :$SERVER_PORT 2>/dev/null | grep -q $SERVER_PORT" 2>/dev/null; then
	warn "Port $SERVER_PORT already in use on remote — trying to clean up"
	ssh "$REMOTE_HOST" "tmux kill-session -t infernode-test 2>/dev/null" || true
	sleep 3
	if ssh "$REMOTE_HOST" "ss -tlnp sport = :$SERVER_PORT 2>/dev/null | grep -q $SERVER_PORT" 2>/dev/null; then
		echo "ERROR: Port $SERVER_PORT still in use on $REMOTE_HOST"
		exit 1
	fi
fi
pass "Port $SERVER_PORT available on remote"

echo ""

# ── Phase 2: Key Generation & Distribution ─────────────────────────

echo -e "${BOLD}Phase 2: Key Generation & Distribution${NC}"

if [ -f "$KEYFILE" ] && [ "$FORCE_KEYS" -eq 0 ]; then
	pass "Local key exists: $KEYFILE (use -f to regenerate)"
else
	info "Generating Ed25519 self-signed key..."
	mkdir -p "$(dirname "$KEYFILE")"
	timeout 30 "$EMU" -r"$ROOT" /dis/auth/createsignerkey.dis \
		-a ed25519 -f /usr/inferno/keyring/default testnode \
		</dev/null >/dev/null 2>&1 || true

	if [ ! -f "$KEYFILE" ] || [ ! -s "$KEYFILE" ]; then
		fail "Key file not created: $KEYFILE"
		exit 1
	fi
	pass "Ed25519 key generated"
fi

# Copy key to remote if missing or forced
REMOTE_KEYFILE="$REMOTE_ROOT/usr/inferno/keyring/default"
NEED_KEY=0
if [ "$FORCE_KEYS" -eq 1 ]; then
	NEED_KEY=1
elif ! ssh "$REMOTE_HOST" "test -f $REMOTE_KEYFILE" 2>/dev/null; then
	NEED_KEY=1
fi

if [ "$NEED_KEY" -eq 1 ]; then
	ssh "$REMOTE_HOST" "mkdir -p $REMOTE_ROOT/usr/inferno/keyring" 2>/dev/null
	scp "$KEYFILE" "$REMOTE_HOST:$REMOTE_KEYFILE" >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		fail "Could not copy key to remote"
		exit 1
	fi
	pass "Shared key distributed to $REMOTE_HOST"
else
	pass "Remote key exists (use -f to re-distribute)"
fi

echo ""

# ── Phase 3: Start Remote Server ───────────────────────────────────

echo -e "${BOLD}Phase 3: Start Remote Server${NC}"

# Write server script to remote (avoids shell quoting issues with !)
REMOTE_SCRIPT="/tmp/infernode-cross-host-server.sh"
cat > /tmp/infernode-cross-host-server-local.sh << SERVEREOF
#!/bin/bash
cd $REMOTE_ROOT
exec ./emu/Linux/o.emu -r . -c0 /dis/sh.dis -c 'listen -v -k /usr/inferno/keyring/default tcp!*!$SERVER_PORT {export /}'
SERVEREOF

scp /tmp/infernode-cross-host-server-local.sh "$REMOTE_HOST:$REMOTE_SCRIPT" >/dev/null 2>&1
rm -f /tmp/infernode-cross-host-server-local.sh

ssh "$REMOTE_HOST" "chmod +x $REMOTE_SCRIPT; tmux new-session -d -s infernode-test 'bash $REMOTE_SCRIPT'" 2>/dev/null

# Wait for server to start listening
WAITED=0
while ! ssh "$REMOTE_HOST" "ss -tlnp sport = :$SERVER_PORT 2>/dev/null | grep -q $SERVER_PORT" 2>/dev/null; do
	sleep 2
	WAITED=$((WAITED + 2))
	if [ "$WAITED" -ge 20 ]; then
		fail "Remote server failed to start listening within 20s"
		SERVER_LOG=$(ssh "$REMOTE_HOST" "tmux capture-pane -t infernode-test -p 2>/dev/null" 2>/dev/null)
		if [ -n "$SERVER_LOG" ]; then
			echo "  Server output: $SERVER_LOG"
		fi
		exit 1
	fi
done

pass "Remote server listening on $REMOTE_ADDR:$SERVER_PORT (waited ${WAITED}s)"
echo ""

# ── Phase 4: Automated Tests ────────────────────────────────────────

echo -e "${BOLD}Phase 4: Automated Tests${NC}"

# ── Test 1: Unauthenticated mount ──

echo ""
echo "  Test 1: Unauthenticated mount"

OUTPUT=$(run_emu 30 "mount -A tcp!${REMOTE_ADDR}!${SERVER_PORT} /n/remote; cat /n/remote/dev/sysname" 2>&1) || true
info "  Output: $OUTPUT"

if [ -n "$OUTPUT" ] && ! echo "$OUTPUT" | grep -q "mount:"; then
	pass "Test 1: No-auth mount — sysname: $(echo "$OUTPUT" | tr -d '\n')"
	passed=$((passed + 1))
else
	fail "Test 1: No-auth mount failed"
	echo "    Output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 2: Authenticated mount (no encryption) ──

echo ""
echo "  Test 2: Auth-only mount (Ed25519, no encryption)"

OUTPUT=$(run_emu 45 "mount -C none -k /usr/inferno/keyring/default tcp!${REMOTE_ADDR}!${SERVER_PORT} /n/remote; cat /n/remote/dev/sysname" 2>&1) || true
info "  Output: $OUTPUT"

if [ -n "$OUTPUT" ] && ! echo "$OUTPUT" | grep -q "mount:\|Broken"; then
	pass "Test 2: Auth-only mount — sysname: $(echo "$OUTPUT" | tr -d '\n')"
	passed=$((passed + 1))
else
	fail "Test 2: Auth-only mount failed"
	echo "    Output: $OUTPUT"
	# Check server side for errors
	SERVER_LOG=$(ssh "$REMOTE_HOST" "tmux capture-pane -t infernode-test -p 2>/dev/null" 2>/dev/null)
	echo "    Server: $SERVER_LOG"
	failed=$((failed + 1))
fi

# ── Test 3: Authenticated + encrypted mount ──

echo ""
echo "  Test 3: Auth + encrypted mount (rc4_256 sha1)"

OUTPUT=$(run_emu 45 "mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default tcp!${REMOTE_ADDR}!${SERVER_PORT} /n/remote; cat /n/remote/dev/sysname" 2>&1) || true
info "  Output: $OUTPUT"

if [ -n "$OUTPUT" ] && ! echo "$OUTPUT" | grep -q "mount:\|Broken"; then
	pass "Test 3: Encrypted mount — sysname: $(echo "$OUTPUT" | tr -d '\n')"
	passed=$((passed + 1))
else
	fail "Test 3: Encrypted mount failed"
	echo "    Output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 4: Read remote files through encrypted channel ──

echo ""
echo "  Test 4: Read remote files through encrypted channel"

OUTPUT=$(run_emu 45 "mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default tcp!${REMOTE_ADDR}!${SERVER_PORT} /n/remote; cat /n/remote/dev/user" 2>&1) || true
info "  Output: $OUTPUT"

if [ -n "$OUTPUT" ] && ! echo "$OUTPUT" | grep -q "mount:\|Broken\|cannot"; then
	pass "Test 4: Read remote /dev/user — $(echo "$OUTPUT" | tr -d '\n')"
	passed=$((passed + 1))
else
	fail "Test 4: Read remote file failed"
	echo "    Output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 5: List remote directory through encrypted channel ──

echo ""
echo "  Test 5: List remote directory through encrypted channel"

OUTPUT=$(run_emu 45 "mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default tcp!${REMOTE_ADDR}!${SERVER_PORT} /n/remote; ls /n/remote/dev" 2>&1) || true
info "  Output: $OUTPUT"

if echo "$OUTPUT" | grep -q "sysname"; then
	NFILES=$(echo "$OUTPUT" | wc -l | tr -d ' ')
	pass "Test 5: Listed remote /dev — $NFILES entries"
	passed=$((passed + 1))
else
	fail "Test 5: List remote directory failed"
	echo "    Output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 6: Mount to wrong address fails cleanly ──

echo ""
echo "  Test 6: Mount to unreachable address fails cleanly"

OUTPUT=$(run_emu 15 "mount -A tcp!10.255.255.254!${SERVER_PORT} /n/remote; cat /n/remote/dev/sysname" 2>&1) || true
info "  Output: '$OUTPUT'"

if [ -z "$OUTPUT" ] || echo "$OUTPUT" | grep -q "mount:\|cannot\|does not exist"; then
	pass "Test 6: Unreachable address handled gracefully"
	passed=$((passed + 1))
else
	fail "Test 6: Expected failure but got: $OUTPUT"
	failed=$((failed + 1))
fi

echo ""

# ── Server-side verification ──

echo -e "${BOLD}Server-Side Verification${NC}"
SERVER_LOG=$(ssh "$REMOTE_HOST" "tmux capture-pane -t infernode-test -p 2>/dev/null" 2>/dev/null)
AUTH_COUNT=$(echo "$SERVER_LOG" | grep -c "authenticated" || true)
CONN_COUNT=$(echo "$SERVER_LOG" | grep -c "got connection" || true)
BROKEN_COUNT=$(echo "$SERVER_LOG" | grep -c "Broken" || true)

echo "  Connections received: $CONN_COUNT"
echo "  Authenticated:       $AUTH_COUNT"
echo "  Errors:              $BROKEN_COUNT"

if [ "$BROKEN_COUNT" -gt 0 ]; then
	warn "Server reported errors:"
	echo "$SERVER_LOG" | grep "Broken" | sed 's/^/    /'
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
	echo "Starting local emu with encrypted mount to $REMOTE_HOST..."
	echo "Remote namespace mounted at /n/remote"
	echo "Try: ls /n/remote"
	echo "     cat /n/remote/dev/sysname"
	echo ""

	TMPSCRIPT=$(mktemp /tmp/infernode-test-XXXXXX.sh)
	cat > "$TMPSCRIPT" << INTEREOF
#!/bin/bash
cd "$ROOT"
exec ./emu/MacOSX/o.emu -r . /dis/sh.dis -c "mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default tcp!${REMOTE_ADDR}!${SERVER_PORT} /n/remote; echo 'Connected to $REMOTE_HOST (authenticated + encrypted)'; echo 'Remote namespace at /n/remote'; sh"
INTEREOF
	chmod +x "$TMPSCRIPT"
	bash "$TMPSCRIPT" || true
	rm -f "$TMPSCRIPT"
fi

if [ "$failed" -gt 0 ]; then
	exit 1
fi
exit 0
