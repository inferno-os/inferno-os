#!/bin/bash
#
# Cross-Architecture JIT Test & Benchmark Runner
# Runs on both AMD64 and ARM64
#

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH=$(uname -m)
EMU=""
LIMBO=""

echo "=== InferNode JIT Test & Benchmark Runner ==="
echo "Architecture: $ARCH"
echo "Root: $ROOT"
echo ""

# Locate emulator
if [[ "$ARCH" = "x86_64" ]]; then
    EMU="$ROOT/emu/Linux/o.emu"
    LIMBO="$ROOT/Linux/amd64/bin/limbo"
elif [[ "$ARCH" = "aarch64" ]] || [[ "$ARCH" = "arm64" ]]; then
    if [[ -f "$ROOT/emu/MacOSX/o.emu" ]]; then
        EMU="$ROOT/emu/MacOSX/o.emu"
    elif [[ -f "$ROOT/emu/Linux/o.emu" ]]; then
        EMU="$ROOT/emu/Linux/o.emu"
    fi
    if [[ -f "$ROOT/MacOSX/arm64/bin/limbo" ]]; then
        LIMBO="$ROOT/MacOSX/arm64/bin/limbo"
    elif [[ -f "$ROOT/Linux/arm64/bin/limbo" ]]; then
        LIMBO="$ROOT/Linux/arm64/bin/limbo"
    fi
fi

if [[ ! -x "$EMU" ]]; then
    echo "ERROR: Emulator not found at $EMU"
    echo "Build first with build-linux-amd64.sh or build-linux-arm64.sh"
    exit 1
fi

if [[ ! -x "$LIMBO" ]]; then
    echo "ERROR: Limbo compiler not found at $LIMBO"
    exit 1
fi

echo "Emulator: $EMU"
echo "Limbo: $LIMBO"
echo ""

# Compile test and benchmark programs
echo "=== Compiling Test Programs ==="

compile_limbo() {
    local src="$1"
    local dst="$2"
    echo "  Compiling $src -> $dst"
    "$LIMBO" -I "$ROOT/module" -o "$dst" "$src" 2>&1 || {
        echo "  ERROR: Failed to compile $src"
        return 1
    }
}

compile_limbo "$ROOT/appl/cmd/jittest.b" "$ROOT/dis/jittest.dis"
compile_limbo "$ROOT/appl/cmd/jitbench.b" "$ROOT/dis/jitbench.dis"
compile_limbo "$ROOT/appl/cmd/jitbench2.b" "$ROOT/dis/jitbench2.dis"

echo ""
echo "=== Running JIT Correctness Tests ==="
echo ""

timeout 120 "$EMU" -r"$ROOT" /dis/jittest.dis 2>&1 < /dev/null || true

echo ""
echo "=== Running JIT Benchmark (Original) ==="
echo ""

timeout 180 "$EMU" -r"$ROOT" /dis/jitbench.dis 2>&1 < /dev/null || true

echo ""
echo "=== Running JIT Benchmark (Enhanced Cross-Architecture) ==="
echo ""

timeout 600 "$EMU" -r"$ROOT" /dis/jitbench2.dis 2>&1 < /dev/null || true

echo ""
echo "=== Done ==="
