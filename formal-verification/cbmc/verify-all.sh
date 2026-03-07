#!/bin/bash
#
# CBMC Verification Script for Inferno Kernel
#
# Usage: ./verify-all.sh [quick|full]
#
# quick: Simple harnesses only (for CI, ~1 minute)
# full:  All harnesses including pgrpcpy (requires ~15+ minutes, ~10GB RAM)
#

set -e

MODE="${1:-quick}"
cd "$(dirname "$0")"

echo "=== Inferno Kernel CBMC Verification ==="
echo "CBMC Version: $(cbmc --version | head -1)"
echo "Mode: $MODE"
echo ""

PASS=0
FAIL=0

run_verification() {
    local name="$1"
    local file="$2"
    local entry="$3"
    shift 3
    local flags="$@"

    echo "----------------------------------------"
    echo "Verifying: $name"
    echo "File: $file"
    echo "Entry: $entry"
    echo ""

    local logname
    logname=$(echo "$name" | tr ' ()/' '____')
    if cbmc --function "$entry" "$file" $flags 2>&1 | tee "/tmp/cbmc_${logname}.log" | tail -5 | grep -q "VERIFICATION SUCCESSFUL"; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name"
        FAIL=$((FAIL + 1))
        echo "See /tmp/cbmc_${logname}.log for details"
    fi
    echo ""
}

# ====== Quick mode: Simple harnesses (all modes) ======

# Verify array bounds safety
run_verification \
    "Array Bounds (mnthash)" \
    "harness_mnthash_bounds.c" \
    "harness" \
    --bounds-check --pointer-check

# Verify integer overflow safety
run_verification \
    "Integer Overflow (fd allocation)" \
    "harness_overflow_simple.c" \
    "harness" \
    --signed-overflow-check --unsigned-overflow-check

# Verify reference counting
run_verification \
    "Reference Counting" \
    "harness_refcount.c" \
    "harness" \
    --signed-overflow-check --pointer-check

# ====== Crypto harnesses (constant-time + correctness) ======

echo "====== Post-Quantum Crypto Verification ======"
echo ""

# Verify ML-KEM constant-time operations (FO transform)
run_verification \
    "ML-KEM ct_memcmp" \
    "harness_mlkem_ct.c" \
    "harness_ct_memcmp" \
    --bounds-check --pointer-check

run_verification \
    "ML-KEM ct_cmov" \
    "harness_mlkem_ct.c" \
    "harness_ct_cmov" \
    --bounds-check --pointer-check

run_verification \
    "ML-KEM Barrett Reduce" \
    "harness_mlkem_ct.c" \
    "harness_barrett_reduce" \
    --bounds-check --signed-overflow-check

run_verification \
    "ML-KEM cond_sub_q" \
    "harness_mlkem_ct.c" \
    "harness_cond_sub_q" \
    --bounds-check --signed-overflow-check

run_verification \
    "ML-KEM FO Composition" \
    "harness_mlkem_ct.c" \
    "harness_fo_transform_composition" \
    --bounds-check --pointer-check

# Verify ML-DSA arithmetic
run_verification \
    "ML-DSA Barrett Reduce" \
    "harness_mldsa_ct.c" \
    "harness_mldsa_barrett" \
    --bounds-check --signed-overflow-check

run_verification \
    "ML-DSA Montgomery Reduce" \
    "harness_mldsa_ct.c" \
    "harness_mldsa_montgomery" \
    --bounds-check --signed-overflow-check

run_verification \
    "ML-DSA Barrett No Overflow" \
    "harness_mldsa_ct.c" \
    "harness_mldsa_barrett_no_overflow" \
    --signed-overflow-check

run_verification \
    "ML-DSA Montgomery No Overflow" \
    "harness_mldsa_ct.c" \
    "harness_mldsa_montgomery_no_overflow" \
    --signed-overflow-check

# Verify ML-KEM polynomial encode/decode round-trips
run_verification \
    "ML-KEM Encode/Decode 1-bit" \
    "harness_mlkem_ntt.c" \
    "harness_encode_decode_1" \
    --bounds-check --pointer-check --unwind 258

run_verification \
    "ML-KEM Encode/Decode 4-bit" \
    "harness_mlkem_ntt.c" \
    "harness_encode_decode_4" \
    --bounds-check --pointer-check --unwind 258

run_verification \
    "ML-KEM Poly Add Commutative" \
    "harness_mlkem_ntt.c" \
    "harness_poly_add_commutative" \
    --bounds-check --unwind 258

run_verification \
    "ML-KEM Poly Sub Identity" \
    "harness_mlkem_ntt.c" \
    "harness_poly_sub_identity" \
    --bounds-check --unwind 258

# ====== Full mode: pgrpcpy harnesses (heavy, ~15 min) ======

if [ "$MODE" = "full" ]; then
    echo "====== pgrpcpy Harnesses (full mode) ======"
    echo ""

    # Full verification uses real MNTHASH=32 (MNTLOG=5)
    MNTLOG_DEF="${CBMC_MNTLOG:-5}"
    UNWIND=$(( (1 << MNTLOG_DEF) + 2 ))
    echo "Using MNTLOG=$MNTLOG_DEF (MNTHASH=$((1 << MNTLOG_DEF)), unwind=$UNWIND)"
    echo ""

    # Verify pgrpcpy namespace isolation - basic (actual C code)
    run_verification \
        "pgrpcpy Basic Isolation" \
        "harness_pgrpcpy.c" \
        "harness_basic_isolation" \
        --bounds-check --pointer-check --signed-overflow-check --unwind $UNWIND --object-bits 11 -DMNTLOG=$MNTLOG_DEF

    # Verify pgrpcpy modification independence
    run_verification \
        "pgrpcpy Modification Independence" \
        "harness_pgrpcpy.c" \
        "harness_modification_independence" \
        --bounds-check --pointer-check --signed-overflow-check --unwind $UNWIND --object-bits 11 -DMNTLOG=$MNTLOG_DEF

    # Verify pgrpcpy mnthash bounds
    run_verification \
        "pgrpcpy Mnthash Bounds" \
        "harness_pgrpcpy.c" \
        "harness_mnthash_bounds" \
        --bounds-check --pointer-check --signed-overflow-check --unwind $UNWIND --object-bits 11 -DMNTLOG=$MNTLOG_DEF

    # Verify pgrpcpy error path safety
    run_verification \
        "pgrpcpy Error Paths" \
        "harness_pgrpcpy_error.c" \
        "harness" \
        --bounds-check --pointer-check --signed-overflow-check --unwind $UNWIND --object-bits 11 -DMNTLOG=$MNTLOG_DEF
fi

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
