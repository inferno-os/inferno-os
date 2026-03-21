#!/bin/sh
#
# Wallet persistence regression test
#
# Replicates the exact user workflow:
#   1. Boot with secstore, login
#   2. Create wallet account
#   3. Verify sync to secstore
#   4. Kill emu (simulate restart)
#   5. Boot again with secstore, login
#   6. Verify wallet account is restored
#
# This test catches the bug where wallet keys were lost across
# emu restarts because factotum had no secstore save-back path.
#
set -e

ROOT="${ROOT:-.}"
EMU="$ROOT/emu/MacOSX/o.emu"
PASS="wallettest42"

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

# Clean state
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1
# Use a dedicated test user so we never touch the real user's secstore
TESTUSER="testuser-walletpersist"
rm -rf "$ROOT/usr/inferno/secstore/$TESTUSER" 2>/dev/null || true

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

echo "=== wallet persistence regression test ==="

# ── Session 1: Create wallet ─────────────────────────────
echo ""
echo "--- session 1: create wallet account ---"

mkdir -p "$ROOT/tmp"
cat > "$ROOT/tmp/persist1.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/secstore-setup -u $TESTUSER -k $PASS
sleep 1
auth/factotum
sleep 1
echo secstore tcp!localhost!5356 $TESTUSER $PASS > /mnt/factotum/ctl
sleep 1
/dis/veltro/wallet9p.dis &
sleep 3
echo '--- creating wallet ---'
echo 'eth ethereum persist-regtest' > /n/wallet/new
cat /n/wallet/new
echo '--- address ---'
cat /n/wallet/persist-regtest/address
echo '--- factotum keys ---'
cat /mnt/factotum/ctl
echo '--- forcing sync ---'
echo sync > /mnt/factotum/ctl
sleep 3
echo '--- session 1 done ---'
EOF

OUTPUT=$(run_emu 60 /tmp/persist1.sh)
check "wallet created" "$OUTPUT" "0x"
check "key in factotum" "$OUTPUT" "service=wallet-eth-persist-regtest"
check "sync completed" "$OUTPUT" "session 1 done"

# Verify secstore has the data
if [ -f "$ROOT/usr/inferno/secstore/$TESTUSER/factotum" ]; then
    pass "secstore factotum file exists"
else
    fail "secstore factotum file missing"
fi

# Kill everything
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 2

# ── Session 2: Verify restoration ────────────────────────
echo ""
echo "--- session 2: verify wallet restored ---"

cat > "$ROOT/tmp/persist2.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u $TESTUSER -P $PASS
sleep 5
echo '--- factotum keys after reload ---'
cat /mnt/factotum/ctl
echo '--- starting wallet9p ---'
/dis/veltro/wallet9p.dis &
sleep 3
echo '--- accounts ---'
cat /n/wallet/accounts
echo '--- address ---'
cat /n/wallet/persist-regtest/address
echo '--- session 2 done ---'
EOF

OUTPUT=$(run_emu 60 /tmp/persist2.sh)
check "key survived restart" "$OUTPUT" "service=wallet-eth-persist-regtest"
check "wallet account restored" "$OUTPUT" "persist-regtest"
check "wallet address restored" "$OUTPUT" "0x"

# Kill and clean up
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true

echo ""
echo "=== $TESTS tests, $FAILURES failures ==="
if [ $FAILURES -gt 0 ]; then
    echo "FAIL"
    exit 1
fi
echo "PASS"

# Clean up test data only (uses TESTUSER, never touches real user account)
rm -rf "$ROOT/usr/inferno/secstore/$TESTUSER" 2>/dev/null || true
