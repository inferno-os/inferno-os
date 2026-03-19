#!/bin/sh
#
# Regression test: Verify k8 combined font migration (commit 847c0c99)
#
# Bug context: .b sources referenced old k1 bitmap fonts such as
#   *default*  (as primary font, not fallback)
#   /fonts/lucida/unicode.16.font
#   /fonts/lucida/unicode.12.font
#   /fonts/pelm/...
# These were replaced by k8 combined fonts, primarily:
#   /fonts/combined/unicode.sans.14.font
#
# This test has three parts:
#   1. Font reference check -- flag old k1 bitmap font patterns in .b sources
#   2. Font file existence  -- verify combined font file and subfonts exist
#   3. Source-level audit   -- make sure key modules use combined fonts
#

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== Font regression tests ==="

FAILED=0
PASSED=0

pass() {
    local msg="$1"
    echo "  PASS: $msg"
    PASSED=$((PASSED + 1))
    return 0
}

fail() {
    local msg="$1"
    echo "  FAIL: $msg"
    FAILED=$((FAILED + 1))
    return 0
}

# ---------------------------------------------------------------
# Part 1: Check .b sources for old k1 bitmap font references
# ---------------------------------------------------------------
echo ""
echo "--- Part 1: Old k1 font reference scan ---"

# Files that were part of the font migration
SOURCE_FILES="
    appl/lib/menuhit.b
    appl/wm/about.b
    appl/wm/editor.b
    appl/wm/shell.b
    appl/wm/settings.b
    appl/wm/logon.b
    appl/wm/fractals.b
    appl/wm/keyring.b
    appl/charon/layout.b
    appl/lib/mermaid.b
"

for relpath in $SOURCE_FILES; do
    src="$ROOT/$relpath"
    [ -f "$src" ] || continue
    basename=$(basename "$relpath")

    # Flag /fonts/lucida/ references (old k1 bitmap font paths)
    if grep -q '/fonts/lucida/' "$src"; then
        fail "$basename references /fonts/lucida/ (old k1 bitmap font)"
    else
        pass "$basename has no /fonts/lucida/ references"
    fi

    # Flag /fonts/pelm/ references (old k1 bitmap font paths)
    if grep -q '/fonts/pelm/' "$src"; then
        fail "$basename references /fonts/pelm/ (old k1 bitmap font)"
    else
        pass "$basename has no /fonts/pelm/ references"
    fi

    # Flag unicode.16.font / unicode.12.font used directly (not as fallback)
    # These are the old bitmap-sized font filenames.
    if grep -q 'unicode\.16\.font' "$src"; then
        fail "$basename references unicode.16.font (old k1 bitmap size)"
    else
        pass "$basename has no unicode.16.font references"
    fi

    if grep -q 'unicode\.12\.font' "$src"; then
        fail "$basename references unicode.12.font (old k1 bitmap size)"
    else
        pass "$basename has no unicode.12.font references"
    fi
done

# ---------------------------------------------------------------
# Part 2: Font file existence
# ---------------------------------------------------------------
echo ""
echo "--- Part 2: Combined font file existence ---"

COMBINED_DIR="$ROOT/fonts/combined"

# The primary UI font
FONT_FILE="$COMBINED_DIR/unicode.sans.14.font"
if [ -f "$FONT_FILE" ]; then
    pass "unicode.sans.14.font exists"
else
    fail "unicode.sans.14.font missing from fonts/combined/"
fi

# Verify font file is non-empty and has the correct header
if [ -f "$FONT_FILE" ]; then
    header=$(head -1 "$FONT_FILE")
    case "$header" in
        16*12*)
            pass "unicode.sans.14.font has valid header"
            ;;
        *)
            fail "unicode.sans.14.font header is '$header' (expected '16<tab>12')"
            ;;
    esac

    # Check that at least one subfont file referenced in the font exists
    # Pick the first DejaVuSans subfont line
    subfont_ref=$(grep 'DejaVuSans/' "$FONT_FILE" | head -1 | awk -F'\t' '{print $3}')
    if [ -n "$subfont_ref" ]; then
        # Resolve relative path from fonts/combined/
        subfont_path="$COMBINED_DIR/$subfont_ref"
        if [ -f "$subfont_path" ]; then
            pass "subfont $subfont_ref exists"
        else
            fail "subfont $subfont_ref missing (resolved to $subfont_path)"
        fi
    fi
fi

# Also check the other combined fonts we expect
for fontfile in unicode.14.font unicode.sans.12.font unicode.sans.18.font; do
    if [ -f "$COMBINED_DIR/$fontfile" ]; then
        pass "$fontfile exists in fonts/combined/"
    else
        fail "$fontfile missing from fonts/combined/"
    fi
done

# ---------------------------------------------------------------
# Part 3: Key modules should reference combined fonts
# ---------------------------------------------------------------
echo ""
echo "--- Part 3: Combined font adoption audit ---"

# At least some of the core UI modules should reference /fonts/combined/
COMBINED_COUNT=0
for relpath in $SOURCE_FILES; do
    src="$ROOT/$relpath"
    [ -f "$src" ] || continue
    if grep -q '/fonts/combined/' "$src"; then
        COMBINED_COUNT=$((COMBINED_COUNT + 1))
    fi
done

if [ "$COMBINED_COUNT" -gt 0 ]; then
    pass "$COMBINED_COUNT source file(s) reference /fonts/combined/"
else
    fail "no source files reference /fonts/combined/ -- font migration may have regressed"
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "Results: $PASSED passed, $FAILED failed"

if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "FAIL: $FAILED font regression check(s) failed"
    exit 1
fi

echo "PASS: all font regression checks passed"
exit 0
