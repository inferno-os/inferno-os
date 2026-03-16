#!/bin/bash
#
# tests/host/tools9p_activity_ns_test.sh
#
# Regression tests for tools9p activity ID after namespace restriction.
#
# Root cause (fixed 2026-03-16): asyncexec() called restrictns() BEFORE
# binding /tool.N over /tool.  restrictns step 8 hides /tool.N (not in
# safe list), so the bind failed silently.  /tool fell through to the
# parent instance (activity 0).  The launch tool's currentactid()
# returned 0, creating artifacts in the wrong activity.
#
# Fix: FORKNS + bind /tool.N over /tool BEFORE restrictns().
#
# This test verifies the fix by executing a tool through asyncexec
# (which triggers FORKNS + bind + restriction) and checking that
# /tool/activity returns the child's activity ID, not the parent's.
#
# Run from project root: ./tests/host/tools9p_activity_ns_test.sh [-v]
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
info()  { local msg="$1"; [[ "$VERBOSE" -eq 1 ]] && echo "  $msg" || true; }

echo -e "${BOLD}tools9p activity ID after namespace restriction${NC}"
echo ""

[[ -x "$EMU" ]] || { echo "ERROR: emu not found at $EMU" >&2; exit 1; }
[[ -f "$ROOT/dis/veltro/tools9p.dis" ]] || {
    skip "tools9p.dis not found"; echo "Total: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }

# emu_c: run a short Inferno sh -c command
emu_c() {
    local name="$1" tout="$2" cmd="$3"
    local log="/tmp/.t9pnstest-${name}.log"
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

# --- Test 1: /tool/activity via direct read (no asyncexec) ---
# Baseline: verifies the 9P server serves the correct ID
echo "── activity ID direct read (no restriction) ──"
if emu_c "direct0" 10 "tools9p -a 3 -m /tool read & sleep 2; cat /tool/activity; echo DONE"; then
    if echo "$OUTPUT" | grep -q "^3"; then
        pass "direct /tool/activity returns 3 for -a 3"
    else
        fail "direct /tool/activity expected 3, got: $(echo "$OUTPUT" | head -3)"
    fi
else
    skip "tools9p failed to start"
fi

# --- Test 2: /tool/activity via tool exec (through asyncexec) ---
# The read tool runs in asyncexec which does FORKNS + bind + restriction.
# Writing a path to /tool/read/ctl triggers asyncexec; reading /tool/read/ctl
# returns the result.  The read tool opens /tool/activity inside the restricted
# namespace — this is the exact code path the launch tool uses.
echo ""
echo "── activity ID via tool exec (through asyncexec + restriction) ──"
# Write /tool/activity as arg to the read tool via ctl.
# The read tool runs inside asyncexec (FORKNS + bind + restriction).
# The result is read back from the same ctl file.
# The read tool returns "1: <content>" format.
if emu_c "toolexec0" 15 "tools9p -a 5 -m /tool read & sleep 2; echo '/tool/activity' > /tool/read/ctl; sleep 1; cat /tool/read/ctl; echo DONE"; then
    # Read tool output format: "    1\t5" (tab-separated line-numbered)
    if echo "$OUTPUT" | grep -q $'\\t5'; then
        pass "tool exec: /tool/activity returns 5 for -a 5 (parent mount)"
    else
        fail "tool exec: expected 5 in output, got: $(echo "$OUTPUT" | head -5)"
    fi
else
    skip "tools9p failed to start for tool exec test"
fi

# --- Test 3: /tool/activity via tool exec with CHILD mount point ---
# This is the CRITICAL regression test.  When tools9p mounts at /tool.N
# (not /tool), asyncexec must bind /tool.N over /tool BEFORE restriction.
# If the bind happens AFTER, /tool.N is hidden by restrictdir("/", safe)
# (safe list includes "tool" but not "tool.N") and the bind fails silently.
# /tool falls through to the parent instance (wrong activity ID).
echo ""
echo "── activity ID via tool exec with child mount /tool.7 (REGRESSION) ──"
if emu_c "childns" 15 "tools9p -a 7 -m /tool.7 -p /dis/wm read & sleep 2; echo '/tool/activity' > /tool.7/read/ctl; sleep 1; cat /tool.7/read/ctl; echo DONE"; then
    # Must match tab-7 (tool result), not "7" in "/tool.7" paths
    if echo "$OUTPUT" | grep -q $'\\t7'; then
        pass "child mount /tool.7: tool exec sees activity 7 after restriction"
    else
        # The old bug: /tool/activity returns 0 (parent) instead of 7 (child)
        if echo "$OUTPUT" | grep -q $'\\t0'; then
            fail "child mount /tool.7: tool exec returned 0 (parent ID) — bind-before-restrict regression!"
        else
            fail "child mount /tool.7: expected 7, got: $(echo "$OUTPUT" | head -5)"
        fi
    fi
else
    skip "tools9p at /tool.7 failed to start"
fi

# --- Test 4: Two tools9p instances, child sees own ID not parent's ---
# Start parent at /tool (activity 0) and child at /tool.9 (activity 9).
# The child's tool exec must see 9, not 0.
echo ""
echo "── two instances: child /tool.9 must not see parent's activity 0 ──"
if emu_c "twoinstance" 20 "tools9p -a 0 -m /tool read & sleep 2; tools9p -a 9 -m /tool.9 -p /dis/wm read & sleep 2; echo '/tool/activity' > /tool.9/read/ctl; sleep 1; cat /tool.9/read/ctl; echo DONE"; then
    # Must match tab-9 (tool result), not "9" in "/tool.9" paths
    if echo "$OUTPUT" | grep -q $'\\t9'; then
        pass "child /tool.9 tool exec sees activity 9 (not parent's 0)"
    else
        fail "child /tool.9: expected 9, got: $(echo "$OUTPUT" | head -5)"
    fi
else
    skip "two-instance test failed to start"
fi

echo ""
echo "Total: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[[ "$FAILED" -eq 0 ]]
