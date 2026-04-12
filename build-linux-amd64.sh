#!/bin/bash
#
# Build script for Linux x86_64 (amd64)
# Builds Infernode with SDL3 GUI (Lucifer) by default.
# Run this on any x86_64 Linux system.
#
# Usage:
#   ./build-linux-amd64.sh           # Build with SDL3 GUI (default)
#   ./build-linux-amd64.sh headless  # Build headless (no display)
#

set -e

GUIMODE="${1:-sdl3}"

echo "=== InferNode Linux x86_64 Build ==="
echo "GUI backend: $GUIMODE"
echo ""

# Set up environment
export ROOT="$(cd "$(dirname "$0")" && pwd)"
export SYSHOST=Linux
export OBJTYPE=amd64
export SYSTARG=Linux

# Create output directories
mkdir -p "$ROOT/Linux/amd64/bin"
mkdir -p "$ROOT/Linux/amd64/lib"

export PATH="$ROOT/Linux/amd64/bin:$PATH"

echo "ROOT=$ROOT"
echo "SYSHOST=$SYSHOST"
echo "OBJTYPE=$OBJTYPE"
echo ""

# Check for required tools
echo "Checking build requirements..."
if ! command -v gcc &> /dev/null; then
    echo "ERROR: gcc not found. Install build-essential:"
    echo "  sudo apt-get install build-essential"
    exit 1
fi

if [[ "$GUIMODE" == "sdl3" ]]; then
    if pkg-config --exists sdl3 2>/dev/null; then
        echo "SDL3 found: $(pkg-config --modversion sdl3)"
    elif [[ -f /usr/local/lib/libSDL3.so ]] && [[ -d /usr/local/include/SDL3 ]]; then
        echo "SDL3 found: /usr/local/lib/libSDL3.so"
    else
        echo "WARNING: SDL3 not found."
        echo "  Run: ./install-sdl3.sh"
        echo ""
        echo "Falling back to headless build."
        GUIMODE=headless
    fi
fi

echo "Build tools found."
echo ""

# Common compiler flags
CFLAGS="-g -O -fno-strict-aliasing -fno-omit-frame-pointer -fcommon -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fstack-clash-protection"
CFLAGS="$CFLAGS -I$ROOT/Linux/amd64/include -I$ROOT/utils/include -I$ROOT/include"
CFLAGS="$CFLAGS -DLINUX_AMD64"

# Bootstrap mk if needed
if [[ ! -x "$ROOT/Linux/amd64/bin/mk" ]]; then
    echo "=== Bootstrapping mk build tool ==="

    # Build libregexp
    echo "Building utils/libregexp..."
    cd "$ROOT/utils/libregexp"
    rm -f *.o libregexp.a
    for src in regcomp.c regerror.c regexec.c regsub.c regaux.c rregexec.c rregsub.c; do
        echo "  Compiling $src..."
        gcc $CFLAGS -I. -c "$src" -o "${src%.c}.o"
    done
    ar rcs libregexp.a *.o
    cp libregexp.a "$ROOT/Linux/amd64/lib/"
    echo "  libregexp.a built"

    # Build lib9 (minimal set needed for mk)
    echo "Building lib9..."
    cd "$ROOT/lib9"
    rm -f *.o lib9.a

    # Common files
    COMMON_SRC="convD2M.c convM2D.c convM2S.c convS2M.c fcallfmt.c qsort.c runestrlen.c strtoll.c rune.c"

    # Import files
    IMPORT_SRC="argv0.c charstod.c cistrcmp.c cistrncmp.c cistrstr.c cleanname.c create.c"
    IMPORT_SRC="$IMPORT_SRC dofmt.c dorfmt.c errfmt.c exits.c fmt.c fmtfd.c fmtlock.c fmtprint.c"
    IMPORT_SRC="$IMPORT_SRC fmtquote.c fmtrune.c fmtstr.c fmtvprint.c fprint.c getfields.c"
    IMPORT_SRC="$IMPORT_SRC nulldir.c pow10.c print.c readn.c rerrstr.c runeseprint.c runesmprint.c"
    IMPORT_SRC="$IMPORT_SRC runesnprint.c runevseprint.c seprint.c smprint.c snprint.c sprint.c"
    IMPORT_SRC="$IMPORT_SRC strdup.c strecpy.c sysfatal.c tokenize.c u16.c u32.c u64.c"
    IMPORT_SRC="$IMPORT_SRC utflen.c utfnlen.c utfrrune.c utfrune.c utfecpy.c vfprint.c vseprint.c vsmprint.c vsnprint.c"

    # Posix-specific files
    POSIX_SRC="dirstat-posix.c errstr-posix.c getuser-posix.c getwd-posix.c sbrk-posix.c isnan-posix.c"

    # Additional files needed by mk (seek is used by archive.c)
    EXTRA_SRC="seek.c"

    # Note: lock.c is for the emulator (needs dat.h) - not needed for mk bootstrap

    ALL_SRC="$COMMON_SRC $IMPORT_SRC $POSIX_SRC $EXTRA_SRC"

    for src in $ALL_SRC; do
        if [[ -f "$src" ]]; then
            echo "  Compiling $src..."
            gcc $CFLAGS -c "$src" -o "${src%.c}.o"
        fi
    done

    # Build getcallerpc assembly
    if [[ -f "getcallerpc-Linux-amd64.S" ]]; then
        echo "  Assembling getcallerpc-Linux-amd64.S..."
        gcc -c getcallerpc-Linux-amd64.S -o getcallerpc-Linux-amd64.o
    fi

    ar rcs lib9.a *.o
    cp lib9.a "$ROOT/Linux/amd64/lib/"
    echo "  lib9.a built"

    # Build libbio
    echo "Building libbio..."
    cd "$ROOT/libbio"
    rm -f *.o libbio.a

    BIO_SRC="bbuffered.c bfildes.c bflush.c bgetrune.c bgetc.c bgetd.c binit.c boffset.c"
    BIO_SRC="$BIO_SRC bprint.c bputrune.c bputc.c brdline.c brdstr.c bread.c bseek.c bvprint.c bwrite.c"

    for src in $BIO_SRC; do
        echo "  Compiling $src..."
        gcc $CFLAGS -c "$src" -o "${src%.c}.o"
    done

    ar rcs libbio.a *.o
    cp libbio.a "$ROOT/Linux/amd64/lib/"
    echo "  libbio.a built"

    # Build mk
    echo "Building mk..."
    cd "$ROOT/utils/mk"
    rm -f *.o mk

    # Source files for mk (Posix model, sh shell)
    MK_COMMON="arc.c archive.c bufblock.c env.c file.c graph.c job.c lex.c main.c match.c mk.c parse.c recipe.c rule.c run.c shprint.c symtab.c var.c varsub.c word.c"
    MK_POSIX="Posix.c"
    MK_SHELL="sh.c"

    for src in $MK_COMMON $MK_POSIX $MK_SHELL; do
        echo "  Compiling $src..."
        gcc $CFLAGS -DROOT="\"$ROOT\"" -c "$src" -o "${src%.c}.o"
    done

    echo "  Linking mk..."
    gcc -fcommon -o mk *.o -L"$ROOT/Linux/amd64/lib" -lregexp -lbio -l9

    strip mk
    cp mk "$ROOT/Linux/amd64/bin/"
    echo "mk installed to $ROOT/Linux/amd64/bin/mk"
    cd "$ROOT"
    echo ""
fi

# Set SHELL and AWK for mk
export SHELL=/bin/sh
export SHELLNAME=sh
export AWK=awk

# Create the lib directory if it doesn't exist
mkdir -p "$ROOT/Linux/amd64/lib"

echo "=== Bootstrap Complete ==="
echo ""
echo "mk is available at: $ROOT/Linux/amd64/bin/mk"
echo ""
echo "=== Building Libraries with mk ==="
echo ""

# Build order matters - dependencies first
# Core libraries that don't need limbo
for lib in lib9 libbio libmp libsec libmath libfreetype libmemdraw libmemlayer libdraw; do
    if [[ -d "$ROOT/$lib" ]]; then
        echo "Building $lib..."
        cd "$ROOT/$lib"
        "$ROOT/Linux/amd64/bin/mk" install 2>&1 || { echo "ERROR: $lib build failed" >&2; exit 1; }
    fi
done

echo ""
echo "=== Building Limbo Compiler ==="
cd "$ROOT/limbo"
"$ROOT/Linux/amd64/bin/mk" install 2>&1 || { echo "ERROR: limbo build failed" >&2; exit 1; }

# Verify limbo was built
if [[ ! -x "$ROOT/Linux/amd64/bin/limbo" ]]; then
    echo "ERROR: limbo compiler not built!" >&2
    exit 1
fi
strip "$ROOT/Linux/amd64/bin/limbo"

echo ""
echo "=== Building Libraries that need Limbo ==="

# Build libinterp and libkeyring after limbo
for lib in libinterp libkeyring; do
    if [[ -d "$ROOT/$lib" ]]; then
        echo "Building $lib..."
        cd "$ROOT/$lib"
        "$ROOT/Linux/amd64/bin/mk" install 2>&1 || { echo "ERROR: $lib build failed" >&2; exit 1; }
    fi
done

echo ""
echo "=== Building Emulator ($GUIMODE) ==="
cd "$ROOT/emu/Linux"

# Clean any previous build artifacts
rm -f *.o *.emu emu.root.h emu.root.c emu.root.s 2>/dev/null

if [[ "$GUIMODE" == "headless" ]]; then
    # Headless build: use mkfile-g (hardcoded headless, no GUI dependencies)
    "$ROOT/Linux/amd64/bin/mk" -f mkfile-g 2>&1 || { echo "ERROR: emulator build failed" >&2; exit 1; }
else
    # SDL3 GUI build: main mkfile defaults to GUIBACK=sdl3
    rm -f emu.c errstr.h 2>/dev/null
    "$ROOT/Linux/amd64/bin/mk" 2>&1 || { echo "ERROR: emulator build failed" >&2; exit 1; }
fi

echo ""
echo "=== Building Applications (Limbo -> Dis bytecode) ==="

MK="$ROOT/Linux/amd64/bin/mk"

# Build library modules
echo "Building library modules..."
cd "$ROOT/appl/lib"
$MK install 2>&1 || { echo "WARNING: some library modules failed to build"; }

# Build core commands (includes lucifer, luciuisrv, lucibridge, etc.)
echo "Building command utilities..."
cd "$ROOT/appl/cmd"
$MK install 2>&1 || { echo "WARNING: some commands failed to build"; }

# Build window manager components (editor, shell, wm, etc.)
echo "Building wm components..."
cd "$ROOT/appl/wm"
$MK install 2>&1 || { echo "WARNING: some wm modules failed to build"; }

# Build shell modules
echo "Building shell modules..."
cd "$ROOT/appl/cmd/sh"
$MK install 2>&1 || { echo "WARNING: some shell modules failed to build"; }

# Build Charon web browser
echo "Building Charon web browser..."
cd "$ROOT/appl/charon"
$MK install 2>&1 || { echo "WARNING: some charon modules failed to build"; }

# Build Veltro agent system (tools9p, agentlib, etc.)
echo "Building Veltro agent system..."
cd "$ROOT/appl/veltro"
$MK install 2>&1 || { echo "WARNING: some veltro modules failed to build"; }

# Verify essential files
echo ""
echo "=== Verifying Lucifer components ==="
MISSING=0
for f in emuinit.dis sh.dis lucifer.dis luciuisrv.dis lucibridge.dis luciconv.dis lucipres.dis lucictx.dis llmsrv.dis; do
    if [[ -f "$ROOT/dis/$f" ]]; then
        echo "  OK: dis/$f"
    else
        echo "  MISSING: dis/$f"
        MISSING=$((MISSING + 1))
    fi
done

for f in editor.dis shell.dis fractals.dis; do
    if [[ -f "$ROOT/dis/wm/$f" ]]; then
        echo "  OK: dis/wm/$f"
    else
        echo "  MISSING: dis/wm/$f"
        MISSING=$((MISSING + 1))
    fi
done

for f in tools9p.dis agentlib.dis lucibridge.dis; do
    # tools9p and agentlib go to dis/veltro/
    if [[ "$f" == "lucibridge.dis" ]]; then
        continue  # lucibridge is in dis/, checked above
    fi
    if [[ -f "$ROOT/dis/veltro/$f" ]]; then
        echo "  OK: dis/veltro/$f"
    else
        echo "  MISSING: dis/veltro/$f"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
echo "=== Build Summary ==="
echo ""
if [[ -x "$ROOT/emu/Linux/o.emu" ]]; then
    echo "SUCCESS: Emulator built at $ROOT/emu/Linux/o.emu"
    ls -la "$ROOT/emu/Linux/o.emu"
    echo ""
    echo "GUI backend: $GUIMODE"
    if [[ $MISSING -gt 0 ]]; then
        echo "WARNING: $MISSING Lucifer component(s) missing"
    fi
    echo ""
    if [[ "$GUIMODE" == "sdl3" ]]; then
        echo "To launch Lucifer:"
        echo "  ./run-lucifer-linux.sh"
    else
        echo "To run (headless):"
        echo "  cd $ROOT/emu/Linux"
        echo "  ./o.emu -r../.. sh -l"
    fi
else
    echo "Emulator binary not found. Checking for build output..."
    ls -la "$ROOT/emu/Linux/"*.emu 2>/dev/null || echo "No emulator binary found"
fi
echo ""
