#!/bin/bash
#
# Build InferNode for macOS ARM64 (Headless mode)
#

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
export ROOT

echo "=== InferNode macOS ARM64 Build (Headless) ==="
echo "ROOT=$ROOT"
echo ""

# Set up environment for macOS ARM64
export SYSHOST=MacOSX
export OBJTYPE=arm64
export PATH="$ROOT/MacOSX/arm64/bin:$PATH"
export AWK=awk
export SHELLNAME=sh

echo "Building for: SYSHOST=$SYSHOST OBJTYPE=$OBJTYPE"
echo "GUI Backend: headless (no display)"
echo ""

# Build emulator
cd "$ROOT/emu/MacOSX"

echo "Cleaning previous build..."
mk clean 2>/dev/null || true

echo "Building headless emulator..."
mk GUIBACK=headless

if [[ -f o.emu ]]; then
    echo ""
    echo "=== Build Successful ==="
    ls -lh o.emu
    file o.emu
    echo ""
    echo "Checking for SDL dependencies..."
    otool -L o.emu | grep -i sdl || echo "  ✓ No SDL dependencies (correct for headless)"
    echo ""
    echo "Emulator: $ROOT/emu/MacOSX/o.emu"
    echo "Run with: ./o.emu -r../.."
else
    echo "Build failed!"
    exit 1
fi
