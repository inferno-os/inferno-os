#!/bin/bash
#
# Build InferNode for macOS ARM64 (SDL3 GUI mode)
#
# !!! CRITICAL TODO !!!
# The emu-hosted Limbo compiler (/dis/limbo.dis) produces BROKEN bytecode on ARM64!
# It generates smaller .dis files with invalid opcodes (BADOP errors at runtime).
#
# ALWAYS use the native Limbo compiler for building Limbo modules:
#   ./MacOSX/arm64/bin/limbo -I module -o output.dis source.b
#
# DO NOT use:
#   ./emu/MacOSX/o.emu -r. 'limbo ...'
#
# The hosted limbo.dis needs to be rebuilt for ARM64 compatibility.
# See: appl/cmd/limbo/ and dis/limbo.dis
# !!! END CRITICAL TODO !!!
#

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
export ROOT

echo "=== InferNode macOS ARM64 Build (SDL3 GUI) ==="
echo "ROOT=$ROOT"
echo ""

# Check SDL3 is installed
if ! pkg-config --exists sdl3 2>/dev/null; then
    echo "Error: SDL3 not found!"
    echo "Install with: brew install sdl3 sdl3_ttf"
    exit 1
fi

SDL3_VERSION=$(pkg-config --modversion sdl3)
echo "Found SDL3 version: $SDL3_VERSION"

# Set up environment for macOS ARM64
export SYSHOST=MacOSX
export OBJTYPE=arm64
export PATH="$ROOT/MacOSX/arm64/bin:$PATH"
export AWK=awk
export SHELLNAME=sh

echo "Building for: SYSHOST=$SYSHOST OBJTYPE=$OBJTYPE"
echo "GUI Backend: SDL3"
echo ""

# Build emulator
cd "$ROOT/emu/MacOSX"

echo "Cleaning previous build..."
mk clean 2>/dev/null || true

echo "Building SDL3 GUI emulator..."
mk GUIBACK=sdl3

if [[ -f o.emu ]]; then
    echo ""
    echo "=== Build Successful ==="
    ls -lh o.emu
    file o.emu
    echo ""
    echo "Checking SDL3 dependencies..."
    otool -L o.emu | grep -i sdl
    echo ""

    # Copy to InferNode for app bundle (macOS menu shows executable name)
    cp o.emu InferNode
    echo "Copied o.emu -> InferNode (for InferNode.app bundle)"
    echo ""
    echo "Launch with:"
    echo "  open $ROOT/MacOSX/InferNode.app"
    echo ""
    echo "Or run directly:"
    echo "  ./o.emu -r../.. sh -l -c 'xenith -t dark'"
else
    echo "Build failed!"
    exit 1
fi
