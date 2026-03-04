#!/bin/bash
#
# CBMC Verification Script for Inferno Kernel
#
# Runs all CBMC harnesses to verify implementation properties.
#

set -e

echo "=== Inferno Kernel CBMC Verification ==="
echo "CBMC Version: $(cbmc --version | head -1)"
echo ""

cd "$(dirname "$0")"

PASS=0
FAIL=0

run_verification() {
    local name="$1"
    local file="$2"
    shift 2
    local flags="$@"

    echo "----------------------------------------"
    echo "Verifying: $name"
    echo "File: $file"
    echo "Flags: $flags"
    echo ""

    if cbmc --function harness "$file" $flags 2>&1 | tee /tmp/cbmc_$name.log | tail -5 | grep -q "VERIFICATION SUCCESSFUL"; then
        echo "✅ $name: PASSED"
        ((PASS++))
    else
        echo "❌ $name: FAILED"
        ((FAIL++))
        echo "See /tmp/cbmc_$name.log for details"
    fi
    echo ""
}

# Verify array bounds safety
run_verification \
    "Array Bounds (mnthash)" \
    "harness_mnthash_bounds.c" \
    --bounds-check --pointer-check

# Verify integer overflow safety
run_verification \
    "Integer Overflow (fd allocation)" \
    "harness_overflow_simple.c" \
    --signed-overflow-check --unsigned-overflow-check

# Verify reference counting
run_verification \
    "Reference Counting" \
    "harness_refcount.c" \
    --signed-overflow-check --pointer-check

# Verify pgrpcpy namespace isolation (actual C code)
run_verification \
    "pgrpcpy Isolation" \
    "harness_pgrpcpy.c" \
    --bounds-check --pointer-check --signed-overflow-check --unwind 34

# Verify pgrpcpy error path safety
run_verification \
    "pgrpcpy Error Paths" \
    "harness_pgrpcpy_error.c" \
    --bounds-check --pointer-check --signed-overflow-check --unwind 34

echo "========================================"
echo "CBMC Verification Summary"
echo "========================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "✅ ALL VERIFICATIONS PASSED"
    exit 0
else
    echo "❌ SOME VERIFICATIONS FAILED"
    exit 1
fi
