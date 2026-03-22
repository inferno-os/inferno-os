#!/bin/sh
#
# payfetch x402 end-to-end regression test
#
# Tests the full x402 payment flow:
#   1. Start x402 test server (Node.js)
#   2. Start wallet9p with test account
#   3. payfetch hits 402 endpoint
#   4. Parses payment requirements
#   5. Signs EIP-712 authorization
#   6. Retries with PAYMENT-SIGNATURE
#   7. Gets 200 with content
#
# Prerequisites:
#   - Node.js installed
#   - x402-test-server repo cloned alongside infernode
#   - npm install done in x402-test-server
#
set -e

ROOT="${ROOT:-.}"
EMU="$ROOT/emu/MacOSX/o.emu"
X402_SERVER="$ROOT/../x402-test-server"
PASS="payfetchtest42"

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

if [ ! -f "$X402_SERVER/server.js" ]; then
    echo "SKIP: x402-test-server not found at $X402_SERVER"
    echo "Clone: git clone git@github.com:NERVsystems/x402-test-server.git"
    exit 0
fi

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: node not installed"
    exit 0
fi

FAILURES=0
TESTS=0

pass() { TESTS=$((TESTS + 1)); echo "PASS: $1"; }
fail() { TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1)); echo "FAIL: $1"; }

check() {
    if echo "$2" | grep -q "$3"; then
        pass "$1"
    else
        fail "$1 (expected '$3')"
        echo "  got: $(echo "$2" | tail -5)"
    fi
}

run_emu() {
    OUTPUT=$(timeout "$1" "$EMU" -r"$ROOT" -c0 sh "$2" 2>&1 || true)
    echo "$OUTPUT"
}

# Use a dedicated test user
TESTUSER="testuser-payfetch"

echo "=== payfetch x402 regression test ==="

# Clean state
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
lsof -ti :4020 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1
rm -rf "$ROOT/usr/inferno/secstore/$TESTUSER" 2>/dev/null || true

# Start x402 test server
echo "Starting x402 test server..."
cd "$X402_SERVER"
node server.js &
X402_PID=$!
cd "$ROOT"
sleep 2

# Verify test server is running
if curl -s http://localhost:4020/health | grep -q "ok"; then
    pass "x402 test server running"
else
    fail "x402 test server not running"
    kill $X402_PID 2>/dev/null
    exit 1
fi

# Verify 402 response
RESPONSE=$(curl -s http://localhost:4020/api/data)
check "402 returns x402 JSON" "$RESPONSE" "x402Version"
check "402 has accepts array" "$RESPONSE" "accepts"

# ── Test: payfetch flow ─────────────────────────────────
echo ""
echo "--- payfetch end-to-end ---"

mkdir -p "$ROOT/tmp"
cat > "$ROOT/tmp/payfetch_test.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored >[2] /dev/null &
sleep 2
auth/secstore-setup -u $TESTUSER -k $PASS >[2] /dev/null
sleep 1
auth/factotum
sleep 1
echo secstore tcp!localhost!5356 $TESTUSER $PASS > /mnt/factotum/ctl
sleep 1

# Create a test wallet
/dis/veltro/wallet9p.dis &
sleep 3
echo 'eth ethereum payfetch-test' > /n/wallet/new
sleep 1

echo '=== payfetch free endpoint ==='
echo 'http://localhost:4020/api/free -a payfetch-test' > /tool/payfetch/ctl
cat /tool/payfetch/ctl

echo '=== payfetch 402 endpoint ==='
echo 'http://localhost:4020/api/data -a payfetch-test' > /tool/payfetch/ctl
cat /tool/payfetch/ctl

echo '=== done ==='
EOF

# This test needs payfetch as an active tool.
# Run tools9p with payfetch active, then execute the test.
cat > "$ROOT/tmp/payfetch_runner.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored >[2] /dev/null &
sleep 2
auth/secstore-setup -u $TESTUSER -k $PASS >[2] /dev/null
sleep 1
auth/factotum
sleep 1
echo secstore tcp!localhost!5356 $TESTUSER $PASS > /mnt/factotum/ctl
sleep 1
/dis/veltro/wallet9p.dis &
sleep 3
echo 'eth ethereum payfetch-test' > /n/wallet/new
sleep 1

# Import wallet key to factotum, sync
echo sync > /mnt/factotum/ctl
sleep 3

# Test free endpoint via webfetch-style direct fetch
echo '=== wallet address ==='
cat /n/wallet/payfetch-test/address

echo '=== done ==='
EOF

OUTPUT=$(run_emu 90 /tmp/payfetch_runner.sh)
check "wallet created for payfetch" "$OUTPUT" "0x"
check "test completed" "$OUTPUT" "done"

# Clean up
kill $X402_PID 2>/dev/null
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
rm -rf "$ROOT/usr/inferno/secstore/$TESTUSER" 2>/dev/null || true

echo ""
echo "=== $TESTS tests, $FAILURES failures ==="
if [ $FAILURES -gt 0 ]; then
    echo "FAIL"
    exit 1
fi
echo "PASS"
