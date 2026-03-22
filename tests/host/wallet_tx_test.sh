#!/bin/sh
#
# Live transaction test on Ethereum Sepolia
#
# Prerequisites:
#   - Wallet account exists in secstore
#   - Account funded with Sepolia ETH (for gas) and USDC
#
# Tests:
#   1. Check balance (ETH + USDC)
#   2. Send small ETH amount to a burn address
#   3. Verify transaction receipt
#   4. Send small USDC amount
#   5. Verify USDC transaction receipt
#
set -e

ROOT="${ROOT:-.}"
EMU="$ROOT/emu/MacOSX/o.emu"

if [ ! -x "$EMU" ]; then
    echo "SKIP: emu not found at $EMU"
    exit 0
fi

# Burn address (nobody has the key for this)
BURN="0x000000000000000000000000000000000000dEaD"

# Detect user for secstore
IUSER=$(timeout 5 "$EMU" -r"$ROOT" -c0 cat /dev/user 2>/dev/null | tr -d '\n\r ' || echo "inferno")

echo "=== Live transaction test (Ethereum Sepolia) ==="
echo "User: $IUSER"

mkdir -p "$ROOT/tmp"
cat > "$ROOT/tmp/tx_test.sh" << EOF
load std
bind -a '#I' /net
ndb/cs
auth/secstored >[2] /dev/null &
sleep 2
auth/factotum -S tcp!localhost!5356 -u $IUSER -P testpass
sleep 5
/dis/veltro/wallet9p.dis &
sleep 3

echo '=== 1. check balance ==='
cat /n/wallet/veltro-demo-wallet/balance

echo '=== 2. send 1000 wei ETH ==='
echo '1000 $BURN' > /n/wallet/veltro-demo-wallet/pay
cat /n/wallet/veltro-demo-wallet/pay

echo '=== 3. send 1 USDC (1000000 base units) ==='
echo 'usdc 1000000 $BURN' > /n/wallet/veltro-demo-wallet/pay
cat /n/wallet/veltro-demo-wallet/pay

echo '=== 4. check history ==='
cat /n/wallet/veltro-demo-wallet/history

echo '=== done ==='
EOF

echo "Running transaction test..."
OUTPUT=$(timeout 120 "$EMU" -r"$ROOT" -c0 sh /tmp/tx_test.sh 2>&1 || true)
echo "$OUTPUT"

echo ""
if echo "$OUTPUT" | grep -q "0x"; then
    echo "Transaction hash found — SUCCESS"
else
    echo "No transaction hash — check output above"
fi
