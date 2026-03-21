#!/bin/sh
#
# Regression tests for secstore + factotum + wallet persistence
#
# Tests:
#   1. secstored starts and listens
#   2. secstore account creation (PAK verifier)
#   3. factotum loads keys from secstore
#   4. wallet accounts persist across wallet9p restarts
#   5. keys survive factotum restart via secstore reload
#
set -e

ROOT="${ROOT:-.}"
EMU="$ROOT/emu/MacOSX/o.emu"
PASS="testpass123"

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

# Kill stale secstored
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# Clean secstore state for reproducible test
rm -rf "$ROOT/usr/inferno/secstore/testuser-seclogon" 2>/dev/null || true

FAILURES=0
TESTS=0

pass() {
    TESTS=$((TESTS + 1))
    echo "PASS: $1"
}

fail() {
    TESTS=$((TESTS + 1))
    FAILURES=$((FAILURES + 1))
    echo "FAIL: $1"
}

check() {
    if echo "$2" | grep -q "$3"; then
        pass "$1"
    else
        fail "$1 (expected '$3' in output)"
        echo "  got: $(echo "$2" | tail -5)"
    fi
}

# Run emu with a script, capture output. Exit 124 (timeout) is OK
# because background threads (secstored, wallet9p) never exit.
run_emu() {
    OUTPUT=$(timeout "$1" "$EMU" -r"$ROOT" -c0 sh "$2" 2>&1 || true)
    echo "$OUTPUT"
}

echo "=== secstore/logon/wallet regression tests ==="

# ── Test 1: secstored starts ──────────────────────────────
echo ""
echo "--- test 1: secstored starts ---"
mkdir -p "$ROOT/tmp"
cat > "$ROOT/tmp/test_secstored.sh" << 'EOF'
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
echo 'secstored running'
EOF
OUTPUT=$(run_emu 15 /tmp/test_secstored.sh)
check "secstored starts" "$OUTPUT" "listening on tcp"

# Kill for next test
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 2: secstore account creation ─────────────────────
echo ""
echo "--- test 2: secstore account creation ---"
cat > "$ROOT/tmp/test_secstore_setup.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/secstore-setup -u testuser-seclogon -k $PASS
echo 'setup done'
EOF
OUTPUT=$(run_emu 20 /tmp/test_secstore_setup.sh)
check "secstore-setup creates account" "$OUTPUT" "setup complete"

# Verify PAK file exists on host
if [ -f "$ROOT/usr/inferno/secstore/testuser-seclogon/PAK" ]; then
    pass "PAK verifier file exists"
else
    fail "PAK verifier file missing"
fi

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 3: factotum stores key, syncs to secstore ───────
echo ""
echo "--- test 3: factotum + secstore key persistence ---"
cat > "$ROOT/tmp/test_key_persist.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u testuser-seclogon -P $PASS
sleep 1
echo 'key proto=pass service=test-regression user=testuser !password=secret123' > /mnt/factotum/ctl
echo sync > /mnt/factotum/ctl
sleep 5
echo '--- keys in factotum ---'
cat /mnt/factotum/ctl
echo '--- done ---'
EOF
OUTPUT=$(run_emu 25 /tmp/test_key_persist.sh)
check "key stored in factotum" "$OUTPUT" "service=test-regression"

# Verify secstore has the encrypted factotum file
if [ -f "$ROOT/usr/inferno/secstore/testuser-seclogon/factotum" ]; then
    pass "secstore factotum file exists (keys persisted)"
else
    fail "secstore factotum file missing (keys not persisted)"
fi

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 4: keys survive factotum restart ─────────────────
echo ""
echo "--- test 4: keys survive restart via secstore ---"
cat > "$ROOT/tmp/test_key_reload.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u testuser-seclogon -P $PASS
sleep 2
echo '--- keys after reload ---'
cat /mnt/factotum/ctl
echo '--- done ---'
EOF
OUTPUT=$(run_emu 25 /tmp/test_key_reload.sh)
check "key survives restart" "$OUTPUT" "service=test-regression"

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 5: wallet account persists via factotum/secstore ─
echo ""
echo "--- test 5: wallet account persistence ---"
cat > "$ROOT/tmp/test_wallet_persist.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u testuser-seclogon -P $PASS
sleep 5
/dis/veltro/wallet9p.dis &
sleep 5
echo '--- create wallet ---'
echo 'eth ethereum persist-test' > /n/wallet/new
cat /n/wallet/new
echo '--- address ---'
cat /n/wallet/persist-test/address
echo '--- factotum has wallet key ---'
cat /mnt/factotum/ctl
echo sync > /mnt/factotum/ctl
sleep 2
echo '--- done ---'
EOF
OUTPUT=$(run_emu 60 /tmp/test_wallet_persist.sh)
check "wallet account created" "$OUTPUT" "0x"
check "wallet key in factotum" "$OUTPUT" "service=wallet-eth-persist-test"

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 6: wallet account restored after restart ─────────
echo ""
echo "--- test 6: wallet account restored from secstore ---"
cat > "$ROOT/tmp/test_wallet_restore.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u testuser-seclogon -P $PASS
sleep 5
/dis/veltro/wallet9p.dis &
sleep 5
echo '--- accounts after restart ---'
cat /n/wallet/accounts
echo '--- address ---'
cat /n/wallet/persist-test/address
echo '--- done ---'
EOF
OUTPUT=$(run_emu 60 /tmp/test_wallet_restore.sh)
check "wallet account restored" "$OUTPUT" "persist-test"
check "wallet address restored" "$OUTPUT" "0x"

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Summary ───────────────────────────────────────────────
echo ""
echo "=== $TESTS tests, $FAILURES failures ==="
if [ $FAILURES -gt 0 ]; then
    echo "FAIL"
    exit 1
fi
echo "PASS"

# Clean up test data
rm -rf "$ROOT/usr/inferno/secstore/testuser-seclogon" 2>/dev/null || true
