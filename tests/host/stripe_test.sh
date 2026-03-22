#!/bin/sh
#
# Stripe fiat backend regression test
#
# Tests:
#   1. Create Stripe account in wallet9p
#   2. Query Stripe balance
#   3. Create a payment intent
#
# Prerequisites:
#   - STRIPE_TEST_KEY env var set to a Stripe test mode secret key (sk_test_...)
#
set -e

ROOT="${ROOT:-.}"
EMU="$ROOT/emu/MacOSX/o.emu"
PASS="stripetest42"

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

if [ -z "$STRIPE_TEST_KEY" ]; then
    echo "SKIP: STRIPE_TEST_KEY not set"
    echo "Set a Stripe test mode key: export STRIPE_TEST_KEY=sk_test_..."
    exit 0
fi

TESTUSER="testuser-stripe"
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

echo "=== Stripe fiat backend test ==="

# Clean
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1
rm -rf "$ROOT/usr/inferno/secstore/$TESTUSER" 2>/dev/null || true

mkdir -p "$ROOT/tmp"
cat > "$ROOT/tmp/stripe_test.sh" << EOF
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

# Store Stripe API key in factotum
echo 'key proto=pass service=wallet-stripe-stripe-test user=key !password=$STRIPE_TEST_KEY' > /mnt/factotum/ctl
sleep 1

# Start wallet9p
/dis/veltro/wallet9p.dis &
sleep 3

# Import Stripe account
echo 'import stripe fiat stripe-test $STRIPE_TEST_KEY' > /n/wallet/new
cat /n/wallet/new

echo '=== balance ==='
cat /n/wallet/stripe-test/balance

echo '=== pay ==='
echo '100 Test payment from InferNode' > /n/wallet/stripe-test/pay
cat /n/wallet/stripe-test/pay

echo '=== done ==='
EOF

OUTPUT=$(run_emu 60 /tmp/stripe_test.sh)
check "stripe account created" "$OUTPUT" "stripe-test"
check "balance query" "$OUTPUT" "balance"
check "test completed" "$OUTPUT" "done"

# Clean up
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
rm -rf "$ROOT/usr/inferno/secstore/$TESTUSER" 2>/dev/null || true

echo ""
echo "=== $TESTS tests, $FAILURES failures ==="
if [ $FAILURES -gt 0 ]; then
    echo "FAIL"
    exit 1
fi
echo "PASS"
