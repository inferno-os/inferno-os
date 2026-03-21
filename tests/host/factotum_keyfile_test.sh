#!/bin/sh
# factotum keyfile persistence test (host-side)
# Tests that keys survive a factotum restart when using -f keyfile.
set -e

ROOT="${ROOT:-.}"
EMU="$ROOT/emu/MacOSX/o.emu"

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

echo "=== factotum keyfile persistence test ==="

# Clean up any leftover keyfile from previous runs
rm -f "$ROOT/tmp/test_keyfile.enc"

# Phase 1: Start factotum with -f, add a key, sync, exit
cat > /tmp/factotum_keyfile_test1.sh << 'INFERNO'
load std
auth/factotum -f /tmp/test_keyfile.enc -p testpassword123
sleep 1
echo '--- phase1: add key ---'
echo 'key proto=pass service=testservice user=testuser !password=secret123' > /mnt/factotum/ctl
echo '--- phase1: verify key ---'
cat /mnt/factotum/ctl
echo '--- phase1: sync ---'
echo 'sync' > /mnt/factotum/ctl
sleep 1
echo '--- phase1: done ---'
INFERNO

mkdir -p "$ROOT/tmp" 2>/dev/null || true
cp /tmp/factotum_keyfile_test1.sh "$ROOT/tmp/factotum_keyfile_test1.sh"

echo "--- Phase 1: Add key and sync ---"
timeout 15 "$EMU" -r"$ROOT" -c0 sh /tmp/factotum_keyfile_test1.sh 2>&1 || true

# Check keyfile was created
if [ ! -f "$ROOT/tmp/test_keyfile.enc" ]; then
    echo "FAIL: keyfile was not created"
    exit 1
fi
echo "--- Keyfile created: $(wc -c < "$ROOT/tmp/test_keyfile.enc") bytes ---"

# Phase 2: Start fresh factotum with same -f, verify key persisted
cat > /tmp/factotum_keyfile_test2.sh << 'INFERNO'
load std
auth/factotum -f /tmp/test_keyfile.enc -p testpassword123
sleep 1
echo '--- phase2: check keys ---'
cat /mnt/factotum/ctl
echo '--- phase2: done ---'
INFERNO

cp /tmp/factotum_keyfile_test2.sh "$ROOT/tmp/factotum_keyfile_test2.sh"

echo "--- Phase 2: Reload and verify ---"
OUTPUT=$(timeout 15 "$EMU" -r"$ROOT" -c0 sh /tmp/factotum_keyfile_test2.sh 2>&1 || true)
echo "$OUTPUT"

# Check that the key survived
if echo "$OUTPUT" | grep -q "service=testservice"; then
    echo "=== PASS ==="
else
    echo "FAIL: key did not survive restart"
    exit 1
fi

# Cleanup
rm -f "$ROOT/tmp/test_keyfile.enc"
rm -f "$ROOT/tmp/factotum_keyfile_test1.sh"
rm -f "$ROOT/tmp/factotum_keyfile_test2.sh"

echo "factotum_keyfile_test: done"
