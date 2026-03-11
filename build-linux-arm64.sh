#!/bin/bash
#
# Build script for InferNode on Linux ARM64 (Jetson, Raspberry Pi 4, etc.)
#
# This builds a headless Inferno emulator for ARM64 Linux systems.
#
# Prerequisites:
#   - GCC (build-essential)
#   - make (optional, we use mk)
#
# Usage:
#   ./build-linux-arm64.sh
#

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
export ROOT

echo "=== InferNode Linux ARM64 Build ==="
echo "ROOT=$ROOT"
echo ""

# Check for ARM64
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
    echo "Warning: This script is intended for ARM64 systems (detected: $ARCH)"
    echo "You may need to cross-compile or adjust the build configuration."
    echo ""
fi

# Set up environment for Linux ARM64
export SYSHOST=Linux
export OBJTYPE=arm64
export PATH="$ROOT/Linux/arm64/bin:$PATH"

echo "Building for: SYSHOST=$SYSHOST OBJTYPE=$OBJTYPE"
echo ""

# Check if mk exists
if [[ ! -x "$ROOT/Linux/arm64/bin/mk" ]]; then
    echo "Note: mk not found in $ROOT/Linux/arm64/bin/"
    echo "You may need to bootstrap the build tools first."
    echo ""
    echo "To bootstrap on a working system:"
    echo "  1. Build mk from utils/mk/ using make"
    echo "  2. Copy to Linux/arm64/bin/"
    echo ""

    # Try to build mk if we have a working build system
    if command -v make &> /dev/null && [[ -f "$ROOT/utils/mk/Makefile" ]]; then
        echo "Attempting to bootstrap mk..."
        mkdir -p "$ROOT/Linux/arm64/bin"
        cd "$ROOT/utils/mk"
        make clean 2>/dev/null || true
        make CC=gcc CFLAGS="-I$ROOT/Linux/arm64/include -I$ROOT/include"
        cp mk "$ROOT/Linux/arm64/bin/"
        echo "mk bootstrapped successfully"
        cd "$ROOT"
    else
        echo "Please bootstrap mk manually and re-run this script."
        exit 1
    fi
fi

echo "=== Building Libraries ==="
# Build order matters - dependencies first
for lib in lib9 libbio libmp libsec libmath libfreetype libmemdraw libmemlayer libdraw libinterp libkeyring; do
    if [[ -d "$ROOT/$lib" ]]; then
        echo "Building $lib..."
        cd "$ROOT/$lib"
        mk install || { echo "Error: $lib build failed"; exit 1; }
    fi
done

echo ""
echo "=== Building Emulator (headless) ==="
cd "$ROOT/emu/Linux"

# Use mkfile-g for headless build
if [[ -f mkfile-g ]]; then
    mk -f mkfile-g
else
    mk
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "Emulator built: $ROOT/emu/Linux/o.emu"
echo ""
echo "To run:"
echo "  cd $ROOT"
echo "  ./emu/Linux/o.emu -r."
echo ""
