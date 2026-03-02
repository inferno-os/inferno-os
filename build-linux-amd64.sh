#!/bin/bash
#
# Build script for Linux x86_64 (amd64)
# Run this on any x86_64 Linux system
#

set -e

echo "=== InferNode Linux x86_64 Build ==="
echo ""

# Set up environment
export ROOT="$PWD"
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

echo "Build tools found."
echo ""

# Common compiler flags
CFLAGS="-g -O -fno-strict-aliasing -fno-omit-frame-pointer -fcommon"
CFLAGS="$CFLAGS -I$ROOT/Linux/amd64/include -I$ROOT/utils/include -I$ROOT/include"
CFLAGS="$CFLAGS -DLINUX_AMD64"

# Bootstrap mk if needed
if [ ! -x "$ROOT/Linux/amd64/bin/mk" ]; then
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
        if [ -f "$src" ]; then
            echo "  Compiling $src..."
            gcc $CFLAGS -c "$src" -o "${src%.c}.o"
        fi
    done

    # Build getcallerpc assembly
    if [ -f "getcallerpc-Linux-amd64.S" ]; then
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

    cp mk "$ROOT/Linux/amd64/bin/"
    echo "mk installed to $ROOT/Linux/amd64/bin/mk"
    cd "$ROOT"
    echo ""
fi

# Set SHELL for mk
export SHELL=/bin/sh
export SHELLNAME=sh

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
    if [ -d "$ROOT/$lib" ]; then
        echo "Building $lib..."
        cd "$ROOT/$lib"
        "$ROOT/Linux/amd64/bin/mk" install 2>&1 || echo "Warning: $lib build had issues"
    fi
done

echo ""
echo "=== Building Limbo Compiler ==="
cd "$ROOT/limbo"
"$ROOT/Linux/amd64/bin/mk" install 2>&1 || echo "Warning: limbo build had issues"

# Verify limbo was built
if [ ! -x "$ROOT/Linux/amd64/bin/limbo" ]; then
    echo "ERROR: limbo compiler not built!"
    exit 1
fi

echo ""
echo "=== Building Libraries that need Limbo ==="

# Build libinterp and libkeyring after limbo
for lib in libinterp libkeyring; do
    if [ -d "$ROOT/$lib" ]; then
        echo "Building $lib..."
        cd "$ROOT/$lib"
        "$ROOT/Linux/amd64/bin/mk" install 2>&1 || echo "Warning: $lib build had issues"
    fi
done

echo ""
echo "=== Building Emulator ==="
cd "$ROOT/emu/Linux"

# Clean any previous build artifacts
rm -f *.o *.emu emu.root.h emu.root.c emu.root.s 2>/dev/null

# mkfile-g is the headless emulator config, which includes mkfile-$OBJTYPE
"$ROOT/Linux/amd64/bin/mk" -f mkfile-g 2>&1 || echo "Warning: emulator build had issues"

echo ""
echo "=== Building Applications (Limbo -> Dis bytecode) ==="

# Create dis directories
mkdir -p "$ROOT/dis" "$ROOT/dis/lib"

LIMBO="$ROOT/Linux/amd64/bin/limbo"

# Build library modules
echo "Building library modules..."
cd "$ROOT/appl/lib"
for f in *.b; do
    name="${f%.b}"
    "$LIMBO" -I "$ROOT/module" -o "$ROOT/dis/lib/$name.dis" "$f" 2>/dev/null || true
done
echo "  Built $(ls "$ROOT/dis/lib/"*.dis 2>/dev/null | wc -l) library modules"

# Build core commands
echo "Building command utilities..."
cd "$ROOT/appl/cmd"
for f in *.b; do
    name="${f%.b}"
    "$LIMBO" -I "$ROOT/module" -o "$ROOT/dis/$name.dis" "$f" 2>/dev/null || true
done
echo "  Built $(ls "$ROOT/dis/"*.dis 2>/dev/null | wc -l) command utilities"

# Build shell components
echo "Building shell..."
cd "$ROOT/appl/cmd/sh"
"$LIMBO" -I "$ROOT/module" -o "$ROOT/dis/sh.dis" sh.b 2>/dev/null || true

# Verify essential files
if [ -f "$ROOT/dis/emuinit.dis" ] && [ -f "$ROOT/dis/sh.dis" ]; then
    echo "Essential boot files built successfully"
else
    echo "Warning: Some essential files missing"
fi

echo ""
echo "=== Build Summary ==="
echo ""
if [ -x "$ROOT/emu/Linux/o.emu" ]; then
    echo "SUCCESS: Emulator built at $ROOT/emu/Linux/o.emu"
    ls -la "$ROOT/emu/Linux/o.emu"
    echo ""
    echo "To run:"
    echo "  cd $ROOT"
    echo "  ./emu/Linux/o.emu -r."
else
    echo "Emulator binary not found. Checking for build output..."
    ls -la "$ROOT/emu/Linux/"*.emu 2>/dev/null || echo "No emulator binary found"
fi
echo ""
