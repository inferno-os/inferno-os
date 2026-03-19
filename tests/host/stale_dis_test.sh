#!/bin/sh
#
# Regression test: Detect stale .dis bytecode files
#
# Bug context (commit 847c0c99): .dis files were stale (not recompiled after
# .b source changes), causing the old k1 bitmap font references to persist
# at runtime even though the .b sources had been updated to k8 combined fonts.
#
# This test checks that every .dis file listed below is newer than its
# corresponding .b source.  If a .dis is older, the developer forgot to
# recompile after editing the source.
#
# The file list covers modules that were affected by the font migration and
# other UI-critical paths.
#

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== Stale .dis detection ==="

FAILED=0
PASSED=0
SKIPPED=0

# check_pair SRC DIS
#   Verify that DIS is newer than SRC.
check_pair() {
    src="$ROOT/$1"
    dis="$ROOT/$2"

    if [ ! -f "$src" ]; then
        echo "  SKIP: $1 (source not found)"
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    if [ ! -f "$dis" ]; then
        echo "  FAIL: $2 missing (source exists at $1)"
        FAILED=$((FAILED + 1))
        return
    fi

    # Compare modification times.
    # Use find -newer: if SRC is newer than DIS, it prints SRC.
    if [ -n "$(find "$src" -newer "$dis" -print 2>/dev/null)" ]; then
        echo "  FAIL: $2 is older than $1 -- recompile needed"
        FAILED=$((FAILED + 1))
    else
        echo "  PASS: $2 is up to date"
        PASSED=$((PASSED + 1))
    fi
}

# Modules affected by the k1->k8 font migration (commit 847c0c99)
check_pair appl/lib/menuhit.b    dis/lib/menuhit.dis
check_pair appl/wm/about.b       dis/wm/about.dis
check_pair appl/wm/editor.b      dis/wm/editor.dis
check_pair appl/wm/shell.b       dis/wm/shell.dis
check_pair appl/wm/settings.b    dis/wm/settings.dis
check_pair appl/wm/logon.b       dis/wm/logon.dis
check_pair appl/wm/fractals.b    dis/wm/fractals.dis
check_pair appl/wm/keyring.b     dis/wm/keyring.dis
check_pair appl/charon/layout.b  dis/charon/layout.dis
check_pair appl/lib/mermaid.b    dis/lib/mermaid.dis

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"

if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "FAIL: $FAILED .dis file(s) are stale -- recompile with limbo"
    exit 1
fi

echo "PASS: all .dis files are up to date"
exit 0
