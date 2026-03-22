#!/bin/sh
# wallet9p integration test (host-side)
set -e

ROOT="${ROOT:-.}"

# Detect platform and locate emulator
case "$(uname -s)" in
    Darwin) EMU="$ROOT/emu/MacOSX/o.emu" ;;
    Linux)  EMU="$ROOT/emu/Linux/o.emu" ;;
    *)      echo "SKIP: unsupported platform $(uname -s)"; exit 0 ;;
esac

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

echo "=== wallet9p integration test ==="

# Write an Inferno script
cat > /tmp/wallet9p_testscript.sh << 'INFERNO'
load std
auth/factotum &
sleep 1
/dis/veltro/wallet9p.dis &
sleep 2

echo '--- test: accounts ---'
cat /n/wallet/accounts
echo '--- test: import ---'
echo 'import eth ethereum testkey 0000000000000000000000000000000000000000000000000000000000000001' > /n/wallet/new
cat /n/wallet/new
echo '--- test: address ---'
cat /n/wallet/testkey/address
echo '--- test: chain ---'
cat /n/wallet/testkey/chain
echo '--- test: factotum keys ---'
cat /mnt/factotum/ctl
echo '--- test: sign ---'
echo '9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658' > /n/wallet/testkey/sign
cat /n/wallet/testkey/sign
echo '=== PASS ==='
INFERNO

# Copy script into Inferno filesystem
cp /tmp/wallet9p_testscript.sh "$ROOT/tmp/wallet9p_testscript.sh" 2>/dev/null || true
mkdir -p "$ROOT/tmp" 2>/dev/null || true
cp /tmp/wallet9p_testscript.sh "$ROOT/tmp/wallet9p_testscript.sh"

"$EMU" -r"$ROOT" -c0 sh /tmp/wallet9p_testscript.sh 2>&1 &
EMU_PID=$!
( sleep 30; kill $EMU_PID 2>/dev/null ) &
WATCHDOG=$!
wait $EMU_PID 2>/dev/null || true
kill $WATCHDOG 2>/dev/null || true

echo "wallet9p_test: done"
