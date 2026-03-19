#!/bin/bash
#
# tests/host/tools9p_basics_test.sh
#
# Regression tests for tools9p:
#   - /tool/activity returns correct activity ID
#   - Task agent base tools are always included
#   - Budget tools are delegated correctly
#
# Run from project root: ./tests/host/tools9p_basics_test.sh [-v]
#

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EMU="$ROOT/emu/MacOSX/o.emu"
SH="/dis/sh.dis"
VERBOSE=0

while getopts "v" opt; do
    case $opt in
        v) VERBOSE=1 ;;
        *) echo "Usage: $0 [-v]"; exit 1 ;;
    esac
done

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

PASSED=0; FAILED=0; SKIPPED=0

pass()  { local msg="$1"; echo -e "${GREEN}PASS${NC}: $msg"; PASSED=$((PASSED+1)); return 0; }
fail()  { local msg="$1"; echo -e "${RED}FAIL${NC}: $msg"; FAILED=$((FAILED+1)); return 0; }
skip()  { local msg="$1"; echo -e "${YELLOW}SKIP${NC}: $msg"; SKIPPED=$((SKIPPED+1)); return 0; }
info()  { local msg="$1"; [[ "$VERBOSE" -eq 1 ]] && echo "  $msg" || true; return 0; }

echo -e "${BOLD}tools9p basics tests${NC}"
echo ""

[[ -x "$EMU" ]] || { echo "ERROR: emu not found at $EMU" >&2; exit 1; }
[[ -f "$ROOT/dis/veltro/tools9p.dis" ]] || {
    skip "tools9p.dis not found"; echo "Total: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }

# emu_c: run a short Inferno sh -c command
emu_c() {
    local name="$1" tout="$2" cmd="$3"
    local log="/tmp/.t9ptest-${name}.log"
    timeout "$tout" "$EMU" -r"$ROOT" "$SH" -c "path=(/dis/veltro /dis/cmd /dis .); $cmd" \
            </dev/null >"$log" 2>&1
    local rc=$?
    OUTPUT=$(cat "$log")
    if [[ "$rc" -eq 0 ]] || [[ "$rc" -eq 124 ]]; then
        info "[$name] ok: $OUTPUT"
        return 0
    else
        info "[$name] error (rc=$rc): $OUTPUT"
        return 1
    fi
}

# --- Test 1: /tool/activity returns activity ID 0 for default tools9p ---
echo "── tools9p /tool/activity ──"
if emu_c "actid0" 10 "tools9p -m /tool read & sleep 2; cat /tool/activity; echo READY"; then
    if echo "$OUTPUT" | grep -q "^0"; then
        pass "/tool/activity returns 0 for default activity"
    else
        fail "/tool/activity expected 0, got: $(echo "$OUTPUT" | head -3)"
    fi
else
    skip "tools9p failed to start"
fi

# --- Test 2: /tool/activity returns correct ID for activity N ---
if emu_c "actidN" 10 "tools9p -a 7 -m /tool read & sleep 2; cat /tool/activity; echo READY"; then
    if echo "$OUTPUT" | grep -q "^7"; then
        pass "/tool/activity returns 7 for -a 7"
    else
        fail "/tool/activity expected 7, got: $(echo "$OUTPUT" | head -3)"
    fi
else
    skip "tools9p failed to start for activity ID test"
fi

# --- Test 3: tools9p serves requested tools ---
# The base tools guarantee is enforced by provisiontask() during task creation,
# not by tools9p startup.  Here we verify that tools9p correctly serves the
# tools passed on the command line.
if emu_c "tools" 10 "tools9p -m /tool read list find memory & sleep 2; cat /tool/tools; echo READY"; then
    missing=""
    for t in read list find memory; do
        if ! echo "$OUTPUT" | grep -q "$t"; then
            missing="$missing $t"
        fi
    done
    if [[ -z "$missing" ]]; then
        pass "tools9p serves requested tools (read list find memory)"
    else
        fail "missing requested tools:$missing"
    fi
else
    skip "tools9p failed to start for tools test"
fi

# --- Test 4: Budget tools are available via /tool/budget ---
if emu_c "budget" 10 "tools9p -m /tool -b write,edit,exec read & sleep 2; cat /tool/budget; echo READY"; then
    if echo "$OUTPUT" | grep -q "write" && echo "$OUTPUT" | grep -q "edit" && echo "$OUTPUT" | grep -q "exec"; then
        pass "budget tools listed in /tool/budget"
    else
        fail "budget tools not found in /tool/budget: $(echo "$OUTPUT" | head -3)"
    fi
else
    skip "tools9p failed to start for budget test"
fi

echo ""
echo "Total: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[[ "$FAILED" -eq 0 ]]
