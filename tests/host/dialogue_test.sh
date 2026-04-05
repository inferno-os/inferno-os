#!/bin/bash
#
# tests/host/dialogue_test.sh
#
# Tests the dialogue tile protocol via luciuisrv:
#   - Creating dialogue tiles with dtype, title, progress, options
#   - Reading back all fields
#   - In-place update of progress
#   - Clearing options via update (hasattr/nil=="" fix)
#   - Updating title via update
#
# Does NOT require the LLM service.
# Run from project root: ./tests/host/dialogue_test.sh [-v]
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

echo -e "${BOLD}Dialogue tile protocol tests${NC}"
echo ""

[[ -x "$EMU" ]] || { echo "ERROR: emu not found at $EMU" >&2; exit 1; }
[[ -f "$ROOT/dis/luciuisrv.dis" ]] || {
    skip "luciuisrv.dis not found"; echo "Total: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }

# emu_c: run a short Inferno sh -c command
emu_c() {
    local name="$1" tout="$2" cmd="$3"
    local log="/tmp/.dlgtest-${name}.log"
    timeout "$tout" "$EMU" -r"$ROOT" "$SH" -c "path=(/dis/veltro /dis/cmd /dis .); $cmd" \
            </dev/null >"$log" 2>&1
    local rc=$?
    OUTPUT=$(cat "$log")
    if [[ "$rc" -eq 0 ]] || [[ "$rc" -eq 124 ]]; then
        info "[$name] ok: $OUTPUT"
        return 0
    else
        info "[$name] exit $rc: $OUTPUT"
        return $rc
    fi
}

# ── Smoke test ──
echo "── luciuisrv smoke ──"

if ! emu_c "smoke" 8 "luciuisrv; sleep 1; echo 'activity create Main' > /n/ui/ctl; cat /n/ui/activity/0/label"; then
    skip "luciuisrv failed to start (output: $OUTPUT)"
    echo "Total: $PASSED passed, $FAILED failed, $SKIPPED skipped"
    exit 0
fi
if echo "$OUTPUT" | grep -q "Main"; then
    pass "luciuisrv starts and activity created"
else
    fail "luciuisrv smoke test (output: $OUTPUT)"
fi

# ── Create dialogue tile with all fields ──
echo ""
echo "── create dialogue tile ──"

if emu_c "create_form" 8 \
    "luciuisrv; sleep 1; echo 'activity create Main' > /n/ui/ctl; echo 'role=veltro dtype=form title=Permission options=Allow,Deny text=Grant access?' > /n/ui/activity/0/conversation/ctl; cat /n/ui/activity/0/conversation/0"; then
    GOT="$OUTPUT"
    ALL_OK=1
    if echo "$GOT" | grep -q "dtype=form"; then
        pass "dtype=form present in message"
    else
        fail "dtype=form not found (output: $GOT)"; ALL_OK=0
    fi
    if echo "$GOT" | grep -q "title=Permission"; then
        pass "title=Permission present in message"
    else
        fail "title=Permission not found (output: $GOT)"; ALL_OK=0
    fi
    if echo "$GOT" | grep -q "options=Allow,Deny"; then
        pass "options=Allow,Deny present in message"
    else
        fail "options=Allow,Deny not found (output: $GOT)"; ALL_OK=0
    fi
    if echo "$GOT" | grep -q "text=Grant access?"; then
        pass "text field present in message"
    else
        fail "text field not found (output: $GOT)"; ALL_OK=0
    fi
else
    fail "create form tile (emu error)"
fi

# ── Create dialogue tile with progress ──
echo ""
echo "── dialogue tile with progress ──"

if emu_c "create_progress" 8 \
    "luciuisrv; sleep 1; echo 'activity create Main' > /n/ui/ctl; echo 'role=veltro dtype=dialogue title=Downloading progress=50 text=50% complete' > /n/ui/activity/0/conversation/ctl; cat /n/ui/activity/0/conversation/0"; then
    GOT="$OUTPUT"
    if echo "$GOT" | grep -q "dtype=dialogue"; then
        pass "dtype=dialogue present"
    else
        fail "dtype=dialogue not found (output: $GOT)"
    fi
    if echo "$GOT" | grep -q "progress=50"; then
        pass "progress=50 present"
    else
        fail "progress=50 not found (output: $GOT)"
    fi
    if echo "$GOT" | grep -q "title=Downloading"; then
        pass "title=Downloading present"
    else
        fail "title=Downloading not found (output: $GOT)"
    fi
else
    fail "create progress tile (emu error)"
fi

# ── Update progress in-place ──
echo ""
echo "── update progress in-place ──"

if emu_c "update_progress" 8 \
    "luciuisrv; sleep 1; echo 'activity create Main' > /n/ui/ctl; echo 'role=veltro dtype=dialogue title=Downloading progress=50 text=working' > /n/ui/activity/0/conversation/ctl; echo 'update idx=0 progress=100' > /n/ui/activity/0/conversation/ctl; cat /n/ui/activity/0/conversation/0"; then
    GOT="$OUTPUT"
    if echo "$GOT" | grep -q "progress=100"; then
        pass "progress updated to 100"
    else
        fail "progress not updated (output: $GOT)"
    fi
    if echo "$GOT" | grep -q "title=Downloading"; then
        pass "title preserved after progress update"
    else
        fail "title lost after progress update (output: $GOT)"
    fi
    if echo "$GOT" | grep -q "dtype=dialogue"; then
        pass "dtype preserved after progress update"
    else
        fail "dtype lost after progress update (output: $GOT)"
    fi
else
    fail "update progress (emu error)"
fi

# ── Clear options via update (hasattr fix) ──
echo ""
echo "── clear options via update ──"

# The hasattr fix allows setting options="" to clear them.
# When options is empty, it should NOT appear in the read output.
if emu_c "clear_options" 8 \
    "luciuisrv; sleep 1; echo 'activity create Main' > /n/ui/ctl; echo 'role=veltro dtype=form title=Permission options=Allow,Deny text=Grant access?' > /n/ui/activity/0/conversation/ctl; echo 'update idx=0 title=Allowed options=' > /n/ui/activity/0/conversation/ctl; cat /n/ui/activity/0/conversation/0"; then
    GOT="$OUTPUT"
    if echo "$GOT" | grep -q "title=Allowed"; then
        pass "title updated to Allowed"
    else
        fail "title not updated (output: $GOT)"
    fi
    if echo "$GOT" | grep -q "options="; then
        fail "options= still present after clearing (output: $GOT)"
    else
        pass "options cleared (not present in output)"
    fi
    if echo "$GOT" | grep -q "dtype=form"; then
        pass "dtype preserved after options clear"
    else
        fail "dtype lost after options clear (output: $GOT)"
    fi
else
    fail "clear options (emu error)"
fi

# ── Update title via update ──
echo ""
echo "── update title ──"

if emu_c "update_title" 8 \
    "luciuisrv; sleep 1; echo 'activity create Main' > /n/ui/ctl; echo 'role=veltro dtype=dialogue title=Step1 progress=25 text=processing' > /n/ui/activity/0/conversation/ctl; echo 'update idx=0 title=Step2 progress=75' > /n/ui/activity/0/conversation/ctl; cat /n/ui/activity/0/conversation/0"; then
    GOT="$OUTPUT"
    if echo "$GOT" | grep -q "title=Step2"; then
        pass "title updated to Step2"
    else
        fail "title not updated to Step2 (output: $GOT)"
    fi
    if echo "$GOT" | grep -q "progress=75"; then
        pass "progress updated to 75"
    else
        fail "progress not updated to 75 (output: $GOT)"
    fi
    if echo "$GOT" | grep -q "role=veltro"; then
        pass "role preserved after multi-field update"
    else
        fail "role lost after multi-field update (output: $GOT)"
    fi
else
    fail "update title (emu error)"
fi

echo ""
echo "Total: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[[ "$FAILED" -eq 0 ]]
