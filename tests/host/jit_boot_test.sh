#!/bin/bash
#
# JIT Boot Smoke Test
#
# Launches the emulator with -c1 (JIT enabled) through the full Lucifer
# boot sequence (skipping wm/logon for CI) and checks for crashes, heap
# corruption, and exception storms. Catches the four classes of JIT
# allocator bug fixed in 963d3a98, 51220b73, a8b3a357:
#   - exNomem from jitmalloc VMA exhaustion
#   - SIGSEGV from negative case-table count after failed compile
#   - SIGSEGV from NULL typecom init/destroy pointer
#   - alloc:D2B heap corruption
#
# Exit 0 = pass, exit 1 = fail.
#

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EMU="$ROOT/emu/Linux/o.emu"
TIMEOUT=60
LOG=$(mktemp /tmp/jit-boot-test.XXXXXX)
BOOTSCRIPT=$(mktemp /tmp/jit-boot-script.XXXXXX)

if [[ ! -x "$EMU" ]]; then
    echo "SKIP: no Linux emulator at $EMU"
    exit 0
fi

# Create a headless boot script that skips wm/logon (no interactive login
# possible in CI) but runs everything else: tools9p, luciuisrv, lucifer.
sed 's/^wm\/logon/#wm\/logon  # skipped for CI/' \
    "$ROOT/lib/lucifer/boot.sh" > "$BOOTSCRIPT"
# Copy into emu root so the emu can see it
cp "$BOOTSCRIPT" "$ROOT/tmp_jit_boot_test.sh"

echo "JIT boot smoke test (timeout ${TIMEOUT}s)..."

timeout "$TIMEOUT" "$EMU" -c1 -pheap=1024m -pmain=1024m -pimage=1024m \
    -r"$ROOT" sh -l /tmp_jit_boot_test.sh \
    > "$LOG" 2>&1 < /dev/null || true

rm -f "$BOOTSCRIPT" "$ROOT/tmp_jit_boot_test.sh"

FAIL=0

# Check for crash signatures
for pat in "exNomem" "SIGSEGV" "alloc:D2B" "panic:" "POOL CORRUPTION"; do
    if grep -q "$pat" "$LOG"; then
        echo "FAIL: found '$pat' in boot log"
        grep "$pat" "$LOG" | head -3
        FAIL=1
    fi
done

# Check that tools9p loaded all 12 active plugins
TOOLS=$(grep -c 'tools9p\[/tool\]: loaded' "$LOG" || true)
if [[ "$TOOLS" -lt 12 ]]; then
    echo "FAIL: only $TOOLS/12 tools9p plugins loaded"
    FAIL=1
fi

# Check that Lucifer initialized
if ! grep -q "lucifer: INIT" "$LOG"; then
    echo "FAIL: Lucifer did not initialize"
    FAIL=1
fi

# Check for shell death
if grep -q '\[Sh\] Broken:' "$LOG"; then
    echo "FAIL: boot shell died"
    grep '\[Sh\] Broken:' "$LOG"
    FAIL=1
fi

if [[ "$FAIL" -eq 0 ]]; then
    MODS=$(grep -c '^JIT compiled ' "$LOG" || true)
    echo "PASS: $MODS modules JIT-compiled, $TOOLS tools loaded, no crashes"
else
    echo "--- boot log tail ---"
    tail -20 "$LOG"
fi

rm -f "$LOG"
exit $FAIL
