#!/bin/sh
# secstore end-to-end test (host-side)
# Tests: setup account → start server → factotum -S stores key → restart → key persists
set -e

ROOT="${ROOT:-.}"
EMU="$ROOT/emu/MacOSX/o.emu"

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

echo "=== secstore end-to-end test ==="

# Clean up from previous runs
rm -rf "$ROOT/tmp/secstore_e2e"

# Phase 1: Setup account, start server, add key via factotum -S, sync
cat > "$ROOT/tmp/secstore_e2e_p1.sh" << 'INFERNO'
load std

# Create secstore account
echo '--- setup account ---'
auth/secstore-setup -k testpass123 -u testuser -s /tmp/secstore_e2e
echo 'setup status: '$status

# Start secstored
echo '--- starting secstored ---'
auth/secstored -d -s /tmp/secstore_e2e -a 'tcp!*!15357' &
sleep 2

# Start factotum with -S pointing to local secstored
echo '--- starting factotum with -S ---'
auth/factotum -d -S 'tcp!127.0.0.1!15357' -P testpass123 -u testuser
sleep 1

# Add a key
echo '--- adding test key ---'
echo 'key proto=pass service=secstore-test user=alice !password=wonderland' > /mnt/factotum/ctl
echo 'add status: '$status

# Verify it's in factotum
echo '--- factotum keys ---'
cat /mnt/factotum/ctl

# Sync to secstore
echo '--- syncing ---'
echo 'sync' > /mnt/factotum/ctl
sleep 2

echo '--- phase 1 done ---'
INFERNO

echo "--- Phase 1: Setup + Store ---"
P1_OUT=$(timeout 25 "$EMU" -r"$ROOT" -c0 sh /tmp/secstore_e2e_p1.sh 2>&1 || true)
echo "$P1_OUT"

# Check that the secstore file was created
if [ -d "$ROOT/tmp/secstore_e2e/testuser" ]; then
    echo "--- secstore user dir exists ---"
    ls -la "$ROOT/tmp/secstore_e2e/testuser/"
else
    echo "FAIL: secstore user directory not created"
    exit 1
fi

# Phase 2: Start fresh server + factotum, verify key persisted
cat > "$ROOT/tmp/secstore_e2e_p2.sh" << 'INFERNO'
load std

# Start secstored (account already exists from phase 1)
echo '--- starting secstored ---'
auth/secstored -d -s /tmp/secstore_e2e -a 'tcp!*!15357' &
sleep 2

# Start factotum with -S — should load keys from secstore
echo '--- starting factotum with -S ---'
auth/factotum -d -S 'tcp!127.0.0.1!15357' -P testpass123 -u testuser
sleep 1

# Check if the key survived
echo '--- factotum keys after reload ---'
cat /mnt/factotum/ctl

echo '--- phase 2 done ---'
INFERNO

echo ""
echo "--- Phase 2: Reload + Verify ---"
P2_OUT=$(timeout 25 "$EMU" -r"$ROOT" -c0 sh /tmp/secstore_e2e_p2.sh 2>&1 || true)
echo "$P2_OUT"

# Check results
if echo "$P2_OUT" | grep -q "secstore-test"; then
    echo ""
    echo "=== PASS: key survived secstore roundtrip ==="
else
    echo ""
    echo "FAIL: key did not survive secstore roundtrip"
    exit 1
fi

# Cleanup
rm -rf "$ROOT/tmp/secstore_e2e"
rm -f "$ROOT/tmp/secstore_e2e_p1.sh" "$ROOT/tmp/secstore_e2e_p2.sh"

echo "secstore_e2e_test: done"
