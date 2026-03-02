#!/bin/bash
#
# Cross-Host GPU Sharing Test
#
# Tests remote GPU inference via authenticated, encrypted 9P.
# The local machine (macOS) mounts a GPU compute filesystem exported
# by a Jetson Orin running TensorRT, then performs inference remotely.
#
#   Local (macOS)                        Remote (Jetson Orin / hephaestus)
#   ┌──────────┐    ZeroTier VPN    ┌────────────────────────────────┐
#   │ emu      │ ──[Ed25519 auth]──>│ emu                            │
#   │ (client) │   [encrypted 9P]   │ gpusrv -p gpu_classifier.plan  │
#   │          │                    │ listen + export /mnt/gpu       │
#   │ mount /n/gpu ←────────────────│                                │
#   │ clone → infer → read output   │ TensorRT + CUDA                │
#   └──────────┘                    └────────────────────────────────┘
#
# Prerequisites:
#   - SSH access to the remote host (e.g. ssh hephaestus)
#   - ZeroTier or other network connectivity between hosts
#   - InferNode built on both machines
#   - gpu_classifier.plan and gpusrv.dis built on remote
#   - Shared Ed25519 key (copied automatically if missing)
#
# Usage:
#   ./tests/test-cross-host-gpu.sh                         # run with defaults
#   ./tests/test-cross-host-gpu.sh -r hephaestus           # specify remote host
#   ./tests/test-cross-host-gpu.sh -a 10.243.169.78        # specify remote IP
#   ./tests/test-cross-host-gpu.sh -p 9997                 # specify port
#   ./tests/test-cross-host-gpu.sh -v                      # verbose output
#   ./tests/test-cross-host-gpu.sh -f                      # force regenerate keys
#   ./tests/test-cross-host-gpu.sh -i                      # interactive mode after tests
#

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="$ROOT/emu/MacOSX/o.emu"
SERVER_PORT=9997
REMOTE_HOST="hephaestus"
REMOTE_ADDR=""
REMOTE_ROOT='~/github.com/NERVsystems/infernode'
REMOTE_EMU_REL="emu/Linux/o.emu"
KEYFILE="$ROOT/usr/inferno/keyring/default"
INTERACTIVE=0
VERBOSE=0
FORCE_KEYS=0
TMUX_SESSION="infernode-gpu-test"

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
	tmpscript=$(mktemp /tmp/infernode-gpu-test-XXXXXX.sh)
	# Use double quotes around cmds so inner single quotes (e.g. 'rc4_256 sha1')
	# pass through correctly. Safe in non-interactive bash (no ! expansion).
	cat > "$tmpscript" << EMUSCRIPT
#!/bin/bash
cd "$ROOT"
exec ./emu/MacOSX/o.emu -r . /dis/sh.dis -c "$cmds"
EMUSCRIPT
	chmod +x "$tmpscript"
	timeout "$tout" bash "$tmpscript" 2>&1
	local rc=$?
	rm -f "$tmpscript"
	return $rc
}

# Helper: run a command on the remote host via SSH.
run_remote() {
	local cmds="$1"
	ssh "$REMOTE_HOST" "$cmds"
}

cleanup() {
	info "Stopping remote GPU server..."
	ssh "$REMOTE_HOST" "tmux kill-session -t $TMUX_SESSION 2>/dev/null; pkill -9 -f 'listen.*$SERVER_PORT.*export' 2>/dev/null; pkill -9 -f 'o.emu.*gpusrv' 2>/dev/null" || true
	rm -f "$ROOT/tmp/testinput.bin" "$ROOT/tmp/gpu-test4.sh" "$ROOT/tmp/gpu-test5.sh"
}
trap cleanup EXIT

echo "=== InferNode Cross-Host GPU Sharing Test ==="
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

# Check remote gpusrv.dis
if ! ssh "$REMOTE_HOST" "test -f $REMOTE_ROOT/dis/gpusrv.dis" 2>/dev/null; then
	echo "ERROR: gpusrv.dis not found on remote"
	echo "Build on remote: cd $REMOTE_ROOT/appl/cmd && mk gpusrv.dis"
	exit 1
fi
pass "Remote gpusrv.dis found"

# Check remote gpu_classifier.plan
if ! ssh "$REMOTE_HOST" "test -f $REMOTE_ROOT/lib/gpu/gpu_classifier.plan" 2>/dev/null; then
	echo "ERROR: gpu_classifier.plan not found on remote"
	echo "Place TensorRT engine at: $REMOTE_ROOT/lib/gpu/gpu_classifier.plan"
	exit 1
fi
pass "Remote gpu_classifier.plan found"

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
	ssh "$REMOTE_HOST" "tmux kill-session -t $TMUX_SESSION 2>/dev/null" || true
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

# ── Phase 3: Start Remote GPU Server ─────────────────────────────

echo -e "${BOLD}Phase 3: Start Remote GPU Server${NC}"

# Write server script to remote (avoids shell quoting issues with !)
REMOTE_SCRIPT="/tmp/infernode-gpu-server.sh"
cat > /tmp/infernode-gpu-server-local.sh << SERVEREOF
#!/bin/bash
cd $REMOTE_ROOT
exec ./emu/Linux/o.emu -r . -c0 /dis/sh.dis -c 'gpusrv -p /lib/gpu/gpu_classifier.plan; listen -v -k /usr/inferno/keyring/default tcp!*!$SERVER_PORT {export /mnt/gpu}'
SERVEREOF

scp /tmp/infernode-gpu-server-local.sh "$REMOTE_HOST:$REMOTE_SCRIPT" >/dev/null 2>&1
rm -f /tmp/infernode-gpu-server-local.sh

ssh "$REMOTE_HOST" "chmod +x $REMOTE_SCRIPT; tmux new-session -d -s $TMUX_SESSION 'bash $REMOTE_SCRIPT'" 2>/dev/null

# Wait for server to start listening (gpusrv + listen may take longer)
WAITED=0
while ! ssh "$REMOTE_HOST" "ss -tlnp sport = :$SERVER_PORT 2>/dev/null | grep -q $SERVER_PORT" 2>/dev/null; do
	sleep 2
	WAITED=$((WAITED + 2))
	if [ "$WAITED" -ge 30 ]; then
		fail "Remote GPU server failed to start listening within 30s"
		SERVER_LOG=$(ssh "$REMOTE_HOST" "tmux capture-pane -t $TMUX_SESSION -p 2>/dev/null" 2>/dev/null)
		if [ -n "$SERVER_LOG" ]; then
			echo "  Server output: $SERVER_LOG"
		fi
		exit 1
	fi
done

pass "Remote GPU server listening on $REMOTE_ADDR:$SERVER_PORT (waited ${WAITED}s)"
echo ""

# ── Phase 3.5: Generate Synthetic Test Tensor ─────────────────────

echo -e "${BOLD}Phase 3.5: Generate Test Tensor${NC}"

mkdir -p "$ROOT/tmp"

# Generate [1,3,224,224] raw float tensor (150528 floats = 602112 bytes)
# Each float is 0.5 (IEEE 754: 0x3F000000)
if command -v python3 >/dev/null 2>&1; then
	python3 -c "
import struct, sys
sys.stdout.buffer.write(struct.pack('<150528f', *([0.5]*150528)))
" > "$ROOT/tmp/testinput.bin"
else
	# Fallback: write 602112 bytes of 0x3F000000 repeated using dd + printf
	printf '\x00\x00\x00\x3f' > /tmp/infernode-float-half.bin
	dd if=/dev/zero bs=602112 count=1 2>/dev/null | \
		python3 -c "" 2>/dev/null || \
		dd if=/tmp/infernode-float-half.bin bs=4 count=150528 2>/dev/null \
		| head -c 602112 > "$ROOT/tmp/testinput.bin"
	rm -f /tmp/infernode-float-half.bin
fi

TENSOR_SIZE=$(wc -c < "$ROOT/tmp/testinput.bin" | tr -d ' ')
if [ "$TENSOR_SIZE" -eq 602112 ]; then
	pass "Synthetic tensor generated ($TENSOR_SIZE bytes, [1,3,224,224] float32)"
else
	fail "Tensor generation failed (got $TENSOR_SIZE bytes, expected 602112)"
	exit 1
fi

echo ""

# ── Phase 4: Automated Tests ──────────────────────────────────────

echo -e "${BOLD}Phase 4: Automated Tests${NC}"

# Create mount point on host (emu -r . maps this to /n/gpu inside Inferno)
mkdir -p "$ROOT/n/gpu"

MOUNT_CMD="mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default tcp!${REMOTE_ADDR}!${SERVER_PORT} /n/gpu"

# ── Test 1: GPU info over encrypted mount ──

echo ""
echo "  Test 1: GPU info over encrypted mount"

OUTPUT=$(run_emu 45 "$MOUNT_CMD; cat /n/gpu/ctl" 2>&1) || true
info "  Output: $OUTPUT"

if echo "$OUTPUT" | grep -qi "cuda" && echo "$OUTPUT" | grep -qi "tensorrt"; then
	pass "Test 1: GPU info — $(echo "$OUTPUT" | head -1 | tr -d '\n')"
	passed=$((passed + 1))
else
	fail "Test 1: GPU info — expected CUDA and TensorRT in output"
	echo "    Output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 2: List remote models ──

echo ""
echo "  Test 2: List remote models"

OUTPUT=$(run_emu 45 "$MOUNT_CMD; ls /n/gpu/models" 2>&1) || true
info "  Output: $OUTPUT"

if echo "$OUTPUT" | grep -q "gpu_classifier"; then
	pass "Test 2: Model listing — gpu_classifier present"
	passed=$((passed + 1))
else
	fail "Test 2: Model listing — gpu_classifier not found"
	echo "    Output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 3: Read model metadata ──

echo ""
echo "  Test 3: Read model metadata"

OUTPUT=$(run_emu 45 "$MOUNT_CMD; cat /n/gpu/models/gpu_classifier" 2>&1) || true
info "  Output: $OUTPUT"

if echo "$OUTPUT" | grep -qi "input\|output"; then
	pass "Test 3: Model metadata — $(echo "$OUTPUT" | grep -i 'input' | head -1 | tr -d '\n')"
	passed=$((passed + 1))
else
	fail "Test 3: Model metadata — expected input/output shape info"
	echo "    Output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 4: Remote inference ──

echo ""
echo "  Test 4: Remote inference (clone → model → input → infer → output)"

# Write Inferno script to avoid backtick quoting issues with bash
cat > "$ROOT/tmp/gpu-test4.sh" << 'INFERSCRIPT'
mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default $1 /n/gpu
id=`{cat /n/gpu/clone}
echo 'model gpu_classifier' > /n/gpu/$id/ctl
cat /tmp/testinput.bin > /n/gpu/$id/input
echo infer > /n/gpu/$id/ctl
cat /n/gpu/$id/status
echo '---'
cat /n/gpu/$id/output
INFERSCRIPT
OUTPUT=$(run_emu 90 "sh /tmp/gpu-test4.sh tcp!${REMOTE_ADDR}!${SERVER_PORT}" 2>&1) || true
info "  Output: $OUTPUT"

STATUS=$(echo "$OUTPUT" | grep -B999 -- '---' | grep -v -- '---' | tail -1 | tr -d '[:space:]')
INFERENCE_OUTPUT=$(echo "$OUTPUT" | grep -A999 -- '---' | grep -v -- '---')

if [ "$STATUS" = "done" ] && [ -n "$INFERENCE_OUTPUT" ]; then
	FIRST_LINE=$(echo "$INFERENCE_OUTPUT" | head -1 | tr -d '\n')
	pass "Test 4: Remote inference — status=$STATUS, first result: $FIRST_LINE"
	passed=$((passed + 1))
elif [ "$STATUS" = "done" ]; then
	warn "Test 4: Inference done but output empty"
	fail "Test 4: Remote inference — no output data"
	echo "    Full output: $OUTPUT"
	failed=$((failed + 1))
else
	fail "Test 4: Remote inference — status=$STATUS (expected done)"
	echo "    Full output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 5: Session isolation ──

echo ""
echo "  Test 5: Session isolation (two independent sessions)"

# Write Inferno script to avoid backtick quoting issues with bash
cat > "$ROOT/tmp/gpu-test5.sh" << 'INFERSCRIPT'
mount -C 'rc4_256 sha1' -k /usr/inferno/keyring/default $1 /n/gpu
id1=`{cat /n/gpu/clone}
id2=`{cat /n/gpu/clone}
echo $id1
echo $id2
INFERSCRIPT
OUTPUT=$(run_emu 60 "sh /tmp/gpu-test5.sh tcp!${REMOTE_ADDR}!${SERVER_PORT}" 2>&1) || true
info "  Output: $OUTPUT"

ID1=$(echo "$OUTPUT" | sed -n '1p' | tr -d '[:space:]')
ID2=$(echo "$OUTPUT" | sed -n '2p' | tr -d '[:space:]')

if [ -n "$ID1" ] && [ -n "$ID2" ] && [ "$ID1" != "$ID2" ]; then
	pass "Test 5: Session isolation — session $ID1 != session $ID2"
	passed=$((passed + 1))
else
	fail "Test 5: Session isolation — ids: '$ID1' '$ID2'"
	echo "    Output: $OUTPUT"
	failed=$((failed + 1))
fi

# ── Test 6: Mount to unreachable address fails cleanly ──

echo ""
echo "  Test 6: Mount to unreachable address fails cleanly"

OUTPUT=$(run_emu 15 "mount -A tcp!10.255.255.254!${SERVER_PORT} /n/gpu; cat /n/gpu/ctl" 2>&1) || true
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
SERVER_LOG=$(ssh "$REMOTE_HOST" "tmux capture-pane -t $TMUX_SESSION -p 2>/dev/null" 2>/dev/null)
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
	echo "Starting local emu with encrypted mount to $REMOTE_HOST GPU..."
	echo "Remote GPU filesystem mounted at /n/gpu"
	echo "Try: cat /n/gpu/ctl"
	echo "     ls /n/gpu/models"
	echo "     cat /n/gpu/clone        # allocate session"
	echo ""

	TMPSCRIPT=$(mktemp /tmp/infernode-gpu-test-XXXXXX.sh)
	cat > "$TMPSCRIPT" << INTEREOF
#!/bin/bash
cd "$ROOT"
exec ./emu/MacOSX/o.emu -r . /dis/sh.dis -c "$MOUNT_CMD; echo 'Connected to $REMOTE_HOST GPU (authenticated + encrypted)'; echo 'GPU filesystem at /n/gpu'; sh"
INTEREOF
	chmod +x "$TMPSCRIPT"
	bash "$TMPSCRIPT" || true
	rm -f "$TMPSCRIPT"
fi

if [ "$failed" -gt 0 ]; then
	exit 1
fi
exit 0
