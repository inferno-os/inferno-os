#!/bin/bash
#
# Inferno Kernel Namespace Formal Verification Runner
#
# This script runs the TLC model checker to verify namespace isolation properties.
#
# Prerequisites:
#   1. Java 11+ installed (java -version)
#   2. TLA+ tools downloaded:
#      curl -L -o tla2tools.jar \
#        "https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar"
#
# Usage:
#   ./run-verification.sh [small|medium|large]
#
# Verification levels:
#   small  - Quick check (~1 minute)   - 2 processes, 3 pgrps, 3 channels
#   medium - Standard check (~10 min)  - 3 processes, 4 pgrps, 4 channels
#   large  - Thorough check (~1 hour+) - 4 processes, 5 pgrps, 5 channels

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TLA_DIR="$SCRIPT_DIR/tla+"
RESULTS_DIR="$SCRIPT_DIR/results"

# Check for tla2tools.jar
if [ ! -f "$SCRIPT_DIR/tla2tools.jar" ]; then
    echo "ERROR: tla2tools.jar not found!"
    echo ""
    echo "Please download it first:"
    echo "  cd $SCRIPT_DIR"
    echo '  curl -L -o tla2tools.jar "https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar"'
    exit 1
fi

# Check for Java
if ! command -v java &> /dev/null; then
    echo "ERROR: Java not found! Please install Java 11 or later."
    exit 1
fi

# Parse verification level
LEVEL="${1:-small}"

case "$LEVEL" in
    small)
        MAX_PROC=2
        MAX_PGRP=3
        MAX_CHAN=3
        MAX_PATH=2
        MAX_MOUNT=4
        HEAP="${TLC_HEAP:-4g}"
        ;;
    medium)
        MAX_PROC=3
        MAX_PGRP=4
        MAX_CHAN=4
        MAX_PATH=3
        MAX_MOUNT=6
        HEAP="${TLC_HEAP:-16g}"
        ;;
    large)
        MAX_PROC=4
        MAX_PGRP=5
        MAX_CHAN=5
        MAX_PATH=3
        MAX_MOUNT=8
        HEAP="${TLC_HEAP:-32g}"
        ;;
    *)
        echo "Unknown level: $LEVEL"
        echo "Usage: $0 [small|medium|large]"
        exit 1
        ;;
esac

echo "========================================"
echo "Inferno Namespace Formal Verification"
echo "========================================"
echo ""
echo "Verification level: $LEVEL"
echo "  MaxProcesses: $MAX_PROC"
echo "  MaxPgrps:     $MAX_PGRP"
echo "  MaxChannels:  $MAX_CHAN"
echo "  MaxPaths:     $MAX_PATH"
echo "  MaxMountId:   $MAX_MOUNT"
echo ""

# Create results directory
mkdir -p "$RESULTS_DIR"

# Generate temporary config file with selected parameters
CONFIG_FILE="$RESULTS_DIR/MC_Namespace_$LEVEL.cfg"
cat > "$CONFIG_FILE" << EOF
\* Auto-generated TLC configuration for $LEVEL verification
\* Generated: $(date)

SPECIFICATION Spec

CONSTANT MaxProcesses = $MAX_PROC
CONSTANT MaxPgrps = $MAX_PGRP
CONSTANT MaxChannels = $MAX_CHAN
CONSTANT MaxPaths = $MAX_PATH
CONSTANT MaxMountId = $MAX_MOUNT

\* Safety Invariants
INVARIANT TypeOK
INVARIANT SafetyInvariant
INVARIANT RefCountNonNegative
INVARIANT NoUseAfterFree
INVARIANT MountTableBounded
INVARIANT NamespaceIsolation
INVARIANT NamespaceIsolationTheorem
INVARIANT UnilateralMountNonPropagation
INVARIANT CopyFidelity
INVARIANT PostCopyMountsSound
INVARIANT NoIsolationViolation

\* State constraint for bounded model checking
CONSTRAINT StateConstraint
ACTION_CONSTRAINT ActionConstraint

\* Alias for debugging
ALIAS Alias
EOF

echo "Running TLC model checker..."
echo "This may take a while depending on the verification level."
echo ""

# Run TLC with unbuffered output to avoid losing progress data
cd "$TLA_DIR"
set +e
OUTPUT_FILE="$RESULTS_DIR/tlc_output_$LEVEL.txt"

# Build TLC command
TLC_CMD="java -XX:+UseParallelGC -Xmx${HEAP} -jar $SCRIPT_DIR/tla2tools.jar -config $CONFIG_FILE -workers auto -checkpoint 60 -deadlock"

# Add recovery flag if RECOVER env var is set
if [ -n "$RECOVER" ]; then
    TLC_CMD="$TLC_CMD -recover $RECOVER"
    echo "Recovering from checkpoint: $RECOVER"
    echo ""
fi

TLC_CMD="$TLC_CMD MC_Namespace.tla"

# Use stdbuf to disable buffering, tee with line buffering
stdbuf -oL $TLC_CMD 2>&1 | stdbuf -oL tee "$OUTPUT_FILE"

TLC_EXIT=${PIPESTATUS[0]}
set -e

echo ""
echo "========================================"
echo "Verification Complete"
echo "========================================"
echo ""
echo "Results saved to: $RESULTS_DIR/tlc_output_$LEVEL.txt"

if [ $TLC_EXIT -eq 0 ]; then
    echo "STATUS: ALL PROPERTIES VERIFIED"
    echo ""
    echo "The following properties were verified:"
    echo "  - TypeOK: Type invariant holds"
    echo "  - SafetyInvariant: Combined safety properties hold"
    echo "  - RefCountNonNegative: Reference counts never go negative"
    echo "  - NoUseAfterFree: Freed objects are not used"
    echo "  - MountTableBounded: Mount tables contain valid references"
    echo "  - NamespaceIsolation: Namespaces are properly isolated"
else
    echo "STATUS: VERIFICATION FAILED OR INCOMPLETE"
    echo "Check the output file for details."
fi

exit $TLC_EXIT
