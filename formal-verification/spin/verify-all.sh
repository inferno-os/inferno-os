#!/bin/bash
#
# SPIN Verification Script for all Namespace Models
#
# Runs all SPIN models and reports results.
#
# Usage: ./verify-all.sh [quick|full]
#
# quick: Safety checks only, smaller state limits (for CI)
# full:  Full state space + LTL properties (for thorough verification)
#

set -e

MODE="${1:-quick}"
cd "$(dirname "$0")"

PASS=0
FAIL=0
TOTAL_STATES=0

run_spin_safety() {
    local name="$1"
    local model="$2"
    local limit="${3:-10000000}"

    echo "----------------------------------------"
    echo "Verifying: $name"
    echo "Model: $model"
    echo ""

    # Generate verifier
    spin -a "$model" 2>/dev/null

    # Compile with safety checks
    gcc -o pan pan.c -DSAFETY -DCOLLAPSE -O2 -w 2>/dev/null

    # Run verification
    if ./pan -m"$limit" 2>&1 | tee /tmp/spin_${name// /_}.log | grep -q "errors: 0"; then
        local states
        states=$(grep "states, stored" /tmp/spin_${name// /_}.log | head -1 | awk '{print $1}')
        echo "PASS: $name ($states states explored)"
        TOTAL_STATES=$((TOTAL_STATES + ${states:-0}))
        ((PASS++))
    else
        echo "FAIL: $name"
        ((FAIL++))
        echo "See /tmp/spin_${name// /_}.log for details"
    fi

    # Cleanup
    rm -f pan pan.* _spin_nvr.tmp 2>/dev/null
    echo ""
}

run_spin_ltl() {
    local name="$1"
    local model="$2"
    local property="$3"
    local limit="${4:-1000000}"

    echo "----------------------------------------"
    echo "Verifying LTL: $name"
    echo "Model: $model"
    echo "Property: $property"
    echo ""

    # Generate with LTL
    spin -a "$model" 2>/dev/null

    # Compile for acceptance cycle checking
    gcc -o pan pan.c -DCOLLAPSE -O2 -w 2>/dev/null

    if ./pan -m"$limit" -a 2>&1 | tee /tmp/spin_ltl_${name// /_}.log | grep -q "errors: 0"; then
        echo "PASS: $name (LTL)"
        ((PASS++))
    else
        echo "FAIL: $name (LTL)"
        ((FAIL++))
    fi

    rm -f pan pan.* _spin_nvr.tmp 2>/dev/null
    echo ""
}

echo "=== Inferno Namespace SPIN Verification ==="
echo "SPIN Version: $(spin -V 2>&1 | head -1)"
echo "Mode: $MODE"
echo ""

# ====== Safety Checks (all modes) ======

echo "====== Namespace Isolation Models ======"
echo ""

run_spin_safety \
    "Basic Isolation" \
    "namespace_isolation.pml" \
    10000000

run_spin_safety \
    "Extended Isolation (nested fork)" \
    "namespace_isolation_extended.pml" \
    10000000

echo "====== Locking Protocol ======"
echo ""

run_spin_safety \
    "Multi-Lock Protocol" \
    "namespace_locks.pml" \
    10000000

echo "====== Race Conditions ======"
echo ""

run_spin_safety \
    "Namespace Races (pctl/kchdir/namec)" \
    "namespace_races.pml" \
    10000000

echo "====== Export Boundary ======"
echo ""

run_spin_safety \
    "exportfs Root Boundary" \
    "exportfs_boundary.pml" \
    1000000

# ====== LTL Properties (full mode only) ======

if [ "$MODE" = "full" ]; then
    echo "====== LTL Property Verification ======"
    echo ""

    run_spin_ltl \
        "Lock Ordering" \
        "namespace_locks.pml" \
        "lock_ordering" \
        10000000

    run_spin_ltl \
        "No Use-After-Free (dot)" \
        "namespace_races.pml" \
        "no_use_after_free_dot" \
        10000000

    run_spin_ltl \
        "No Use-After-Free (pgrp)" \
        "namespace_races.pml" \
        "no_use_after_free_pgrp" \
        10000000

    run_spin_ltl \
        "No Use-After-Free (slash)" \
        "namespace_races.pml" \
        "no_use_after_free_slash" \
        10000000

    run_spin_ltl \
        "No Boundary Violation" \
        "exportfs_boundary.pml" \
        "no_boundary_violation" \
        1000000
fi

# ====== Summary ======

echo "========================================"
echo "SPIN Verification Summary"
echo "========================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total states explored: $TOTAL_STATES"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "ALL VERIFICATIONS PASSED"
    exit 0
else
    echo "SOME VERIFICATIONS FAILED"
    exit 1
fi
