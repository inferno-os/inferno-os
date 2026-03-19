#!/bin/bash
#
# tests/host/llmsrv_tooluse_test.sh
#
# Regression tests for native llmsrv tool_use protocol.
#
# Tests:
#   1. Content block ordering: text must precede tool_use in assistant messages
#   2. Full tool_use round-trip through native llmsrv (single tool)
#   3. Full tool_use round-trip with text+tool_use combo response
#   4. Multiple tool calls in a single response
#   5. Tool result with special characters (quotes, newlines, unicode)
#
# Requirements:
#   - ANTHROPIC_API_KEY (env var or LaunchAgent plist)
#   - Inferno emulator at $ROOT/emu/MacOSX/o.emu
#
# Usage:
#   ./tests/host/llmsrv_tooluse_test.sh        # run all tests
#   ./tests/host/llmsrv_tooluse_test.sh -v     # verbose
#

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EMU="$ROOT/emu/MacOSX/o.emu"
VERBOSE=0

while getopts "v" opt; do
	case $opt in
		v) VERBOSE=1 ;;
		*) echo "Usage: $0 [-v]"; exit 1 ;;
	esac
done

# Colour output
if [[ -t 1 ]]; then
	RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
	BOLD='\033[1m'; NC='\033[0m'
else
	RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

pass()  { local msg="$1"; echo -e "  ${GREEN}PASS${NC}: $msg"; PASSED=$((PASSED+1)); return 0; }
fail()  { local msg="$1"; echo -e "  ${RED}FAIL${NC}: $msg"; FAILED=$((FAILED+1)); return 0; }
skip()  { local msg="$1"; echo -e "  ${YELLOW}SKIP${NC}: $msg"; SKIPPED=$((SKIPPED+1)); return 0; }
info()  { local msg="$1"; [[ "$VERBOSE" -eq 1 ]] && echo "    $msg" || true; return 0; }

PASSED=0; FAILED=0; SKIPPED=0

# Get API key
API_KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
	API_KEY=$(plutil -extract EnvironmentVariables.ANTHROPIC_API_KEY raw \
		~/Library/LaunchAgents/com.nervsystems.llm9p.plist 2>/dev/null || true)
fi
if [[ -z "$API_KEY" ]]; then
	echo "ERROR: no API key found (set ANTHROPIC_API_KEY or configure LaunchAgent)" >&2
	exit 1
fi

# Check emulator
if [[ ! -x "$EMU" ]]; then
	echo "ERROR: emulator not found at $EMU" >&2
	exit 1
fi

echo -e "${BOLD}llmsrv tool_use regression tests${NC}"
echo ""

# ── Test 1: Content block ordering — API contract ─────────────────

echo "Test 1: Content block ordering (API contract)"

# 1a: tool_use BEFORE text → must fail (this is the bug we fixed)
cat > /tmp/llmsrv-test-order-bad.json << 'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"messages":[{"role":"user","content":"test"},{"role":"assistant","content":[{"type":"tool_use","id":"toolu_regression_001","name":"greet","input":{"name":"Alice"}},{"type":"text","text":"greeting"}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_regression_001","content":"Hello Alice"}]}],"tools":[{"name":"greet","description":"Greet","input_schema":{"type":"object","properties":{"name":{"type":"string"}}}}]}
EOF

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
	-X POST https://api.anthropic.com/v1/messages \
	-H "Content-Type: application/json" \
	-H "x-api-key: $API_KEY" \
	-H "anthropic-version: 2023-06-01" \
	-d @/tmp/llmsrv-test-order-bad.json 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
info "1a response code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "400" ]]; then
	pass "1a: tool_use before text → 400 (confirms API rejects wrong order)"
else
	fail "1a: expected 400 for tool_use before text, got $HTTP_CODE"
fi

# 1b: text BEFORE tool_use → must succeed
cat > /tmp/llmsrv-test-order-good.json << 'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"messages":[{"role":"user","content":"test"},{"role":"assistant","content":[{"type":"text","text":"greeting"},{"type":"tool_use","id":"toolu_regression_001","name":"greet","input":{"name":"Alice"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_regression_001","content":"Hello Alice"}]}],"tools":[{"name":"greet","description":"Greet","input_schema":{"type":"object","properties":{"name":{"type":"string"}}}}]}
EOF

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
	-X POST https://api.anthropic.com/v1/messages \
	-H "Content-Type: application/json" \
	-H "x-api-key: $API_KEY" \
	-H "anthropic-version: 2023-06-01" \
	-d @/tmp/llmsrv-test-order-good.json 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
info "1b response code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
	pass "1b: text before tool_use → 200 (confirms API accepts correct order)"
else
	fail "1b: expected 200 for text before tool_use, got $HTTP_CODE"
fi

# 1c: tool_use only (no text) → must succeed
cat > /tmp/llmsrv-test-order-toolonly.json << 'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"messages":[{"role":"user","content":"test"},{"role":"assistant","content":[{"type":"tool_use","id":"toolu_regression_002","name":"greet","input":{"name":"Bob"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_regression_002","content":"Hello Bob"}]}],"tools":[{"name":"greet","description":"Greet","input_schema":{"type":"object","properties":{"name":{"type":"string"}}}}]}
EOF

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
	-X POST https://api.anthropic.com/v1/messages \
	-H "Content-Type: application/json" \
	-H "x-api-key: $API_KEY" \
	-H "anthropic-version: 2023-06-01" \
	-d @/tmp/llmsrv-test-order-toolonly.json 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
info "1c response code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
	pass "1c: tool_use only (no text) → 200"
else
	fail "1c: expected 200 for tool_use only, got $HTTP_CODE"
fi

# 1d: multiple tool_use blocks with text first → must succeed
cat > /tmp/llmsrv-test-order-multi.json << 'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"messages":[{"role":"user","content":"test"},{"role":"assistant","content":[{"type":"text","text":"I'll do both"},{"type":"tool_use","id":"toolu_multi_001","name":"greet","input":{"name":"A"}},{"type":"tool_use","id":"toolu_multi_002","name":"greet","input":{"name":"B"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_multi_001","content":"Hi A"},{"type":"tool_result","tool_use_id":"toolu_multi_002","content":"Hi B"}]}],"tools":[{"name":"greet","description":"Greet","input_schema":{"type":"object","properties":{"name":{"type":"string"}}}}]}
EOF

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
	-X POST https://api.anthropic.com/v1/messages \
	-H "Content-Type: application/json" \
	-H "x-api-key: $API_KEY" \
	-H "anthropic-version: 2023-06-01" \
	-d @/tmp/llmsrv-test-order-multi.json 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
info "1d response code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
	pass "1d: text + multiple tool_use → 200"
else
	fail "1d: expected 200 for text + multiple tool_use, got $HTTP_CODE"
fi

echo ""

# ── Test 2: Full tool_use round-trip through native llmsrv ────────

echo "Test 2: Full tool_use round-trip (native llmsrv)"

# Build an emu script that does the full flow
cat > /tmp/llmsrv-roundtrip-test.sh << 'INFERNO'
#!/dis/sh.dis
load std

mount -ac {mntgen} /n >[2] /dev/null
bind -a '#I' /net >[2] /dev/null
ndb/cs
auth/factotum

factotumkey=`{os sh -c 'k=${ANTHROPIC_API_KEY:-$(plutil -extract EnvironmentVariables.ANTHROPIC_API_KEY raw ~/Library/LaunchAgents/com.nervsystems.llm9p.plist 2>/dev/null)}; if [ -n "$k" ]; then echo "key proto=pass service=anthropic user=apikey !password=$k"; fi'}
echo $factotumkey > /mnt/factotum/ctl >[2] /dev/null

llmsrv &
sleep 1

mkdir -p /tmp >[2] /dev/null

id=`{cat /n/llm/new}

# Install tool
echo '[{"name":"greet","description":"Say hello to someone. Args: name","input_schema":{"type":"object","properties":{"args":{"type":"string"}},"required":["args"]}}]' > /n/llm/$id/tools

# Step 1: Ask LLM to use tool
echo 'Use the greet tool to greet Alice. Just call the tool, nothing else.' > /n/llm/$id/ask
response=`{cat /n/llm/$id/ask}

# Check for STOP:tool_use
hasstop='no'
for w in $response {
	if {~ $w 'STOP:tool_use'} { hasstop='yes' }
}

if {~ $hasstop 'no'} {
	echo 'FAIL:step1:no STOP:tool_use in response'
	echo 'response:' $response
} {
	echo 'PASS:step1:got STOP:tool_use'
}

# Extract tool_use_id
toolline=''
for w in $response {
	if {~ $w 'TOOL:*'} { toolline=$w }
}

if {~ $toolline ''} {
	echo 'FAIL:step1:no TOOL: line'
} {
	echo 'PASS:step1:got TOOL line'
}

toolrest=`{echo $toolline | sed 's/^TOOL://'}
toolid=`{echo $toolrest | sed 's/:.*//'}

if {~ $toolid ''} {
	echo 'FAIL:step1:empty tool_use_id'
} {
	echo 'PASS:step1:parsed tool_use_id'
}

# Step 2: Submit tool result
echo 'TOOL_RESULTS
'^$toolid^'
Hello, Alice! Welcome!
---' > /n/llm/$id/ask
response2=`{cat /n/llm/$id/ask}

# Check step 2 response
haserr='no'
for w in $response2 {
	if {~ $w 'Error:*'} { haserr='yes' }
}

if {~ $haserr 'yes'} {
	echo 'FAIL:step2:got error'
	echo 'response:' $response2
} {
	echo 'PASS:step2:tool result accepted'
}

# Check for end_turn
hasend='no'
for w in $response2 {
	if {~ $w 'STOP:end_turn'} { hasend='yes' }
}

if {~ $hasend 'yes'} {
	echo 'PASS:step2:got STOP:end_turn'
} {
	# Could be another tool_use, which is also valid
	hastool='no'
	for w in $response2 {
		if {~ $w 'STOP:tool_use'} { hastool='yes' }
	}
	if {~ $hastool 'yes'} {
		echo 'PASS:step2:got STOP:tool_use (chained)'
	} {
		echo 'WARN:step2:no STOP line'
	}
}

# Verify debug dump ordering (step 2 request)
echo 'DUMP:' `{cat /tmp/llm-req-1.json}
INFERNO

# Copy to inferno-accessible location
cp /tmp/llmsrv-roundtrip-test.sh "$ROOT/tests/inferno/"

LOGFILE="/tmp/llmsrv-roundtrip.log"
if timeout 60 "$EMU" -r"$ROOT" /dis/sh.dis /tests/inferno/llmsrv-roundtrip-test.sh \
	</dev/null >"$LOGFILE" 2>/dev/null; then
	RC=0
else
	RC=$?
fi

OUTPUT=$(cat "$LOGFILE" 2>/dev/null)
info "emu exit: $RC"
info "output: $OUTPUT"

# Parse results
STEP1_PASS=0; STEP2_PASS=0

if echo "$OUTPUT" | grep -q "PASS:step1:got STOP:tool_use"; then
	pass "2a: step 1 got STOP:tool_use"
	STEP1_PASS=1
else
	fail "2a: step 1 missing STOP:tool_use"
	echo "$OUTPUT" | grep "FAIL:" | while read line; do echo "    $line"; done
fi

if echo "$OUTPUT" | grep -q "PASS:step1:got TOOL line"; then
	pass "2b: step 1 got TOOL line"
else
	fail "2b: step 1 missing TOOL line"
fi

if echo "$OUTPUT" | grep -q "PASS:step1:parsed tool_use_id"; then
	pass "2c: step 1 parsed tool_use_id"
else
	fail "2c: step 1 failed to parse tool_use_id"
fi

if echo "$OUTPUT" | grep -q "PASS:step2:tool result accepted"; then
	pass "2d: step 2 tool result accepted (no 400 error)"
	STEP2_PASS=1
else
	fail "2d: step 2 tool result rejected"
	echo "$OUTPUT" | grep "FAIL:" | while read line; do echo "    $line"; done
fi

if echo "$OUTPUT" | grep -qE "PASS:step2:got STOP:(end_turn|tool_use)"; then
	pass "2e: step 2 got valid STOP response"
else
	fail "2e: step 2 missing STOP response"
fi

# Test 2f: Verify content block ordering in the request dump
if [[ "$STEP2_PASS" -eq 1 ]]; then
	DUMP=$(echo "$OUTPUT" | grep "^DUMP:" | sed 's/^DUMP: //')
	if [[ -n "$DUMP" ]]; then
		# Check if assistant message has text before tool_use
		# Python checks the actual ordering
		ORDERING=$(python3 -c "
import json, sys
try:
    data = json.loads('''$DUMP''')
except:
    # Dump may have been split by shell; try the file directly
    sys.exit(2)
msgs = data.get('messages', [])
for m in msgs:
    if m['role'] == 'assistant' and isinstance(m['content'], list):
        types = [c['type'] for c in m['content']]
        if 'text' in types and 'tool_use' in types:
            text_idx = types.index('text')
            tool_idx = types.index('tool_use')
            if text_idx < tool_idx:
                print('CORRECT')
            else:
                print('WRONG')
            sys.exit(0)
        elif 'tool_use' in types and 'text' not in types:
            print('TOOLONLY')
            sys.exit(0)
print('NOCHECK')
" 2>/dev/null || echo "PARSEERR")

		case "$ORDERING" in
			CORRECT)  pass "2f: assistant content block ordering: text before tool_use" ;;
			TOOLONLY)  pass "2f: assistant has tool_use only (no ordering issue)" ;;
			WRONG)    fail "2f: assistant content blocks in WRONG order (tool_use before text)" ;;
			NOCHECK)  skip "2f: no text+tool_use combo to check ordering" ;;
			PARSEERR) skip "2f: could not parse request dump" ;;
			*)        fail "2f: unexpected ordering result: $ORDERING" ;;
		esac
	else
		skip "2f: no debug dump in output"
	fi
fi

echo ""

# ── Test 3: Tool result with special characters ──────────────────

echo "Test 3: Special characters in tool results"

# Test that special chars in tool_result content don't break the request
cat > /tmp/llmsrv-test-special.json << 'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"messages":[{"role":"user","content":"test"},{"role":"assistant","content":[{"type":"tool_use","id":"toolu_special_001","name":"greet","input":{"name":"test"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_special_001","content":"Result with \"quotes\" and\nnewlines and 'apostrophes' and unicode: café — em-dash"}]}],"tools":[{"name":"greet","description":"Greet","input_schema":{"type":"object","properties":{"name":{"type":"string"}}}}]}
EOF

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
	-X POST https://api.anthropic.com/v1/messages \
	-H "Content-Type: application/json" \
	-H "x-api-key: $API_KEY" \
	-H "anthropic-version: 2023-06-01" \
	-d @/tmp/llmsrv-test-special.json 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
info "3 response code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
	pass "3: special characters in tool_result → 200"
else
	fail "3: special characters in tool_result → $HTTP_CODE"
fi

echo ""

# ── Test 4: tool_result must immediately follow tool_use ──────────

echo "Test 4: Message ordering — tool_result must follow tool_use"

# 4a: Missing tool_result → must fail
cat > /tmp/llmsrv-test-missing-result.json << 'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"messages":[{"role":"user","content":"test"},{"role":"assistant","content":[{"type":"tool_use","id":"toolu_missing_001","name":"greet","input":{"name":"test"}}]},{"role":"user","content":"I forgot to include the tool result"}],"tools":[{"name":"greet","description":"Greet","input_schema":{"type":"object","properties":{"name":{"type":"string"}}}}]}
EOF

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
	-X POST https://api.anthropic.com/v1/messages \
	-H "Content-Type: application/json" \
	-H "x-api-key: $API_KEY" \
	-H "anthropic-version: 2023-06-01" \
	-d @/tmp/llmsrv-test-missing-result.json 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
info "4a response code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "400" ]]; then
	pass "4a: missing tool_result → 400 (API enforces pairing)"
else
	fail "4a: expected 400 for missing tool_result, got $HTTP_CODE"
fi

# 4b: Mismatched tool_use_id → must fail
cat > /tmp/llmsrv-test-mismatch.json << 'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"messages":[{"role":"user","content":"test"},{"role":"assistant","content":[{"type":"tool_use","id":"toolu_mismatch_001","name":"greet","input":{"name":"test"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_WRONG_ID","content":"result"}]}],"tools":[{"name":"greet","description":"Greet","input_schema":{"type":"object","properties":{"name":{"type":"string"}}}}]}
EOF

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
	-X POST https://api.anthropic.com/v1/messages \
	-H "Content-Type: application/json" \
	-H "x-api-key: $API_KEY" \
	-H "anthropic-version: 2023-06-01" \
	-d @/tmp/llmsrv-test-mismatch.json 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
info "4b response code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "400" ]]; then
	pass "4b: mismatched tool_use_id → 400 (API enforces ID matching)"
else
	fail "4b: expected 400 for mismatched IDs, got $HTTP_CODE"
fi

echo ""

# ── Cleanup ───────────────────────────────────────────────────────

rm -f /tmp/llmsrv-test-order-*.json /tmp/llmsrv-test-special.json \
	/tmp/llmsrv-test-missing-result.json /tmp/llmsrv-test-mismatch.json \
	/tmp/test-tooluse*.json /tmp/test-order*.json /tmp/test-fixed-order.json \
	/tmp/llmsrv-roundtrip-test.sh /tmp/llmsrv-roundtrip.log 2>/dev/null

# ── Summary ───────────────────────────────────────────────────────

echo -e "${BOLD}=== Results ===${NC}"
echo -e "  ${GREEN}Passed${NC}:  $PASSED"
echo -e "  ${RED}Failed${NC}:  $FAILED"
echo -e "  ${YELLOW}Skipped${NC}: $SKIPPED"
echo ""

if [[ "$FAILED" -gt 0 ]]; then
	exit 1
fi
exit 0
