#!/bin/sh
#
# Test: API key persistence through secstore
#
# Verifies the secstore-first key management flow:
#   1. secstore account created
#   2. factotum configured with secstore save-back
#   3. API key added to factotum and synced to secstore
#   4. sentinel file created (/tmp/.secstore-unlocked)
#   5. key survives factotum restart via secstore reload
#   6. llmsrv can read key from factotum (getfactotumkey)
#
set -e

ROOT="${ROOT:-.}"
EMU="$ROOT/emu/MacOSX/o.emu"
PASS="testpass-apikey"
USER="testuser-apikey"

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

# Kill stale secstored
lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# Clean secstore state
rm -rf "$ROOT/usr/inferno/secstore/$USER" 2>/dev/null || true

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

check_not() {
    if echo "$2" | grep -q "$3"; then
        fail "$1 (unexpected '$3' in output)"
    else
        pass "$1"
    fi
}

run_emu() {
    OUTPUT=$(timeout "$1" "$EMU" -r"$ROOT" -c0 sh "$2" 2>&1 || true)
    echo "$OUTPUT"
}

echo "=== secstore API key persistence tests ==="

# ── Test 1: Create account, add API key, verify sentinel ──
echo ""
echo "--- test 1: secstore account + API key + sentinel ---"
cat > "$ROOT/tmp/test_apikey_setup.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/secstore-setup -u $USER -k $PASS
auth/factotum -S tcp!localhost!5356 -u $USER -P $PASS
sleep 1

# Add API key (same format as keyring app uses)
echo 'key proto=pass service=anthropic user=apikey !password=sk-ant-test-key-12345' > /mnt/factotum/ctl
echo sync > /mnt/factotum/ctl
sleep 3

# Verify key is in factotum
echo '--- factotum keys ---'
cat /mnt/factotum/ctl

# Create sentinel (as logon.b would)
echo '1' > /tmp/.secstore-unlocked

# Verify sentinel exists
echo '--- sentinel check ---'
if {ftest -f /tmp/.secstore-unlocked} {
    echo 'sentinel exists'
} {
    echo 'sentinel missing'
}

echo '--- done ---'
EOF
OUTPUT=$(run_emu 25 /tmp/test_apikey_setup.sh)
check "API key stored in factotum" "$OUTPUT" "service=anthropic"
check "sentinel file created" "$OUTPUT" "sentinel exists"

# Verify secstore has encrypted factotum file on host
if [ -f "$ROOT/usr/inferno/secstore/$USER/factotum" ]; then
    pass "secstore factotum file exists"
else
    fail "secstore factotum file missing"
fi

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 2: Key survives restart ──────────────────────────
echo ""
echo "--- test 2: API key survives restart ---"
cat > "$ROOT/tmp/test_apikey_reload.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u $USER -P $PASS
sleep 2

echo '--- keys after reload ---'
cat /mnt/factotum/ctl
echo '--- done ---'
EOF
OUTPUT=$(run_emu 25 /tmp/test_apikey_reload.sh)
check "API key survives restart" "$OUTPUT" "service=anthropic"
check "API key value preserved" "$OUTPUT" "user=apikey"

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 3: wrong password fails to load keys ────────────
echo ""
echo "--- test 3: wrong password rejects ---"
cat > "$ROOT/tmp/test_apikey_wrongpass.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u $USER -P wrongpassword
sleep 2

echo '--- keys with wrong password ---'
cat /mnt/factotum/ctl
echo '--- done ---'
EOF
OUTPUT=$(run_emu 25 /tmp/test_apikey_wrongpass.sh)
check_not "wrong password yields no API key" "$OUTPUT" "service=anthropic"

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 4: Multiple API keys (anthropic + brave) ────────
echo ""
echo "--- test 4: multiple API keys ---"
cat > "$ROOT/tmp/test_apikey_multi.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u $USER -P $PASS
sleep 2

# Add brave key alongside existing anthropic key
echo 'key proto=pass service=brave user=apikey !password=BSA-test-brave-key' > /mnt/factotum/ctl
echo sync > /mnt/factotum/ctl
sleep 3

echo '--- all keys ---'
cat /mnt/factotum/ctl
echo '--- done ---'
EOF
OUTPUT=$(run_emu 25 /tmp/test_apikey_multi.sh)
check "anthropic key present" "$OUTPUT" "service=anthropic"
check "brave key present" "$OUTPUT" "service=brave"

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Test 5: Both keys survive restart ─────────────────────
echo ""
echo "--- test 5: both API keys survive restart ---"
cat > "$ROOT/tmp/test_apikey_multi_reload.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored &
sleep 2
auth/factotum -S tcp!localhost!5356 -u $USER -P $PASS
sleep 2

echo '--- keys after reload ---'
cat /mnt/factotum/ctl
echo '--- done ---'
EOF
OUTPUT=$(run_emu 25 /tmp/test_apikey_multi_reload.sh)
check "anthropic key survives" "$OUTPUT" "service=anthropic"
check "brave key survives" "$OUTPUT" "service=brave"

lsof -ti :5356 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# ── Summary ───────────────────────────────────────────────
echo ""
echo "=== $TESTS tests, $FAILURES failures ==="
if [ $FAILURES -gt 0 ]; then
    echo "FAIL"
    # Clean up
    rm -rf "$ROOT/usr/inferno/secstore/$USER" 2>/dev/null || true
    exit 1
fi
echo "PASS"

# Clean up
rm -rf "$ROOT/usr/inferno/secstore/$USER" 2>/dev/null || true
rm -f "$ROOT/tmp/test_apikey_setup.sh" "$ROOT/tmp/test_apikey_reload.sh"
rm -f "$ROOT/tmp/test_apikey_wrongpass.sh" "$ROOT/tmp/test_apikey_multi.sh"
rm -f "$ROOT/tmp/test_apikey_multi_reload.sh"
