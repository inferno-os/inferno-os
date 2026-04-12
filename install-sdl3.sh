#!/bin/bash
#
# Install SDL3 from source for Linux
# Requires: sudo, cmake, ninja-build, git
#
set -e

echo "=== Installing SDL3 build dependencies ==="
sudo apt-get install -y cmake ninja-build git \
    libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxss-dev \
    libwayland-dev libxkbcommon-dev libegl-dev libgles-dev \
    libxtst-dev libdrm-dev libgbm-dev

echo ""
echo "=== Building SDL3 from source ==="
BUILDDIR="/tmp/sdl3-build-$$"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

# Pin to a specific release for reproducible builds
SDL3_TAG="release-3.4.4"
SDL3_COMMIT="5848e584a1b606de26e3dbd1c7e4ecbc34f807a6"

git clone --depth 1 --branch "$SDL3_TAG" https://github.com/libsdl-org/SDL.git
cd SDL

# Verify we got the expected commit
ACTUAL_COMMIT=$(git rev-parse HEAD)
if [ "$ACTUAL_COMMIT" != "$SDL3_COMMIT" ]; then
  echo "ERROR: SDL3 commit mismatch (expected $SDL3_COMMIT, got $ACTUAL_COMMIT)"
  exit 1
fi
cmake -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr/local
ninja -C build

echo ""
echo "=== Installing SDL3 ==="
sudo ninja -C build install
sudo ldconfig

echo ""
echo "=== Verifying ==="
pkg-config --modversion sdl3 && echo "SDL3 installed successfully" || echo "WARNING: pkg-config can't find sdl3"

# Cleanup
rm -rf "$BUILDDIR"

ARCH=$(uname -m)
echo ""
if [ "$ARCH" = "aarch64" ]; then
  echo "Done. Now run: ./build-linux-arm64.sh"
else
  echo "Done. Now run: ./build-linux-amd64.sh"
fi
