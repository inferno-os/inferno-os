# Jetson/Linux ARM64 Port - Implementation Guide

**Status: IMPLEMENTED** - Linux ARM64 support is now included in infernode.

## Quick Start (Jetson Native Build)

```bash
# Clone infernode on your Jetson
git clone https://github.com/infernode-os/infernode.git
cd infernode

# Run the build script
./build-linux-arm64.sh

# Or manually:
export ROOT=$PWD
export SYSHOST=Linux
export OBJTYPE=arm64
export PATH="$ROOT/Linux/arm64/bin:$PATH"

# Build (after bootstrapping mk)
cd emu/Linux
mk -f mkfile-g

# Run
./o.emu -r.
```

## Files Added for Linux ARM64

The following files were added to support Linux ARM64:

### Build Configuration
- `mkfiles/mkfile-Linux-arm64` - Compiler settings for native ARM64 Linux
- `emu/Linux/mkfile-arm64` - Architecture-specific build variables
- `emu/Linux/mkfile-g` - Headless build mkfile (no X11)

### Platform Code
- `emu/Linux/asm-arm64.S` - ARM64 assembly (tas, umult, FP stubs)
- `emu/Linux/segflush-arm64.c` - Cache flush using `__builtin___clear_cache`
- `emu/Linux/stubs-headless.c` - Graphics stubs for headless operation

### Headers
- `Linux/arm64/include/lib9.h` - Type definitions and compatibility layer

## Key Differences from macOS ARM64

| Aspect | macOS | Linux |
|--------|-------|-------|
| Symbol prefix | Underscore (`_tas`) | No prefix (`_tas` in code, `tas` exported) |
| Assembly syntax | `.s` lowercase | `.S` uppercase (preprocessed) |
| Cache flush | N/A (not needed) | `__builtin___clear_cache()` |
| Endian header | `<machine/endian.h>` | `<endian.h>` |
| Frameworks | CoreFoundation, IOKit | None |
| X11 | Optional | Optional (headless default) |

## Architecture Overview

Inferno's multi-platform support is cleanly separated:

```
infernode/
├── mkfiles/
│   ├── mkfile-Linux-arm64    # Linux ARM64 build config
│   └── mkfile-MacOSX-arm64   # macOS ARM64 build config
├── emu/
│   ├── port/                 # Portable code (shared)
│   ├── Linux/                # Linux-specific
│   │   ├── os.c              # System interface
│   │   ├── asm-arm64.S       # ARM64 assembly
│   │   ├── segflush-arm64.c  # Cache operations
│   │   └── mkfile-g          # Headless build
│   └── MacOSX/               # macOS-specific
│       ├── os.c
│       ├── asm-arm64.s
│       └── ...
├── Linux/arm64/include/      # Linux ARM64 headers
│   └── lib9.h
└── MacOSX/arm64/include/     # macOS ARM64 headers
    └── lib9.h
```

## Build Requirements

### On Jetson/Linux ARM64

```bash
# Essential build tools
sudo apt-get update
sudo apt-get install build-essential

# Optional: X11 development (if not using headless)
sudo apt-get install libx11-dev libxext-dev
```

### Bootstrapping mk

The `mk` build tool must be compiled first. The build script attempts this automatically, or manually:

```bash
cd utils/mk
make CC=gcc CFLAGS="-I../../Linux/arm64/include -I../../include"
mkdir -p ../../Linux/arm64/bin
cp mk ../../Linux/arm64/bin/
```

## The Critical 64-bit Fixes (Already Applied)

These fixes are already in infernode and will work on Linux ARM64:

1. **Pool Quanta = 127** (`emu/port/alloc.c`)
   - Required for 64-bit pointer alignment

2. **BHDRSIZE with uintptr** (`include/pool.h`)
   - Correct pointer arithmetic on 64-bit

3. **WORD/IBY2WD = 8 bytes** (`include/interp.h`, `include/isa.h`)
   - Dis VM word size matches pointer size

4. **Module Headers** (`libinterp/*.h`)
   - Already generated for 64-bit

## Testing

After building, verify the port:

```bash
# Start the emulator
./emu/Linux/o.emu -r.

# At the ; prompt:
; pwd
; ls /dis
; date
; echo hello
; cat /dev/sysctl
```

### Test Checklist

- [ ] Shell starts with `;` prompt
- [ ] Commands produce output (not silent)
- [ ] No BADOP errors
- [ ] Backspace works (edits, doesn't exit)
- [ ] File operations work
- [ ] Network works (if testing TCP)

## Troubleshooting

### No Output from Commands

**Cause:** Pool corruption due to quanta mismatch
**Check:** Verify `emu/port/alloc.c` has quanta = 127

### BADOP Errors

**Cause:** Shell exception handling
**Check:** Using infernode's shell (already fixed)

### Build Fails - Missing Headers

```bash
sudo apt-get install build-essential
```

### Segmentation Fault at Startup

**Cause:** Module headers mismatch
**Solution:** Regenerate headers:
```bash
cd libinterp
rm -f *.h
mk headers  # or manually regenerate
```

## Comparison: This Port vs inferno64

| Aspect | infernode | inferno64 |
|--------|-----------|-----------|
| Base | InferNode | inferno-os |
| Focus | Headless/embedded | Full Inferno |
| 64-bit fixes | Complete | Partial |
| Documentation | Extensive | Standard |
| Linux ARM64 | Now included | Has support |

You can use either as a starting point. infernode has the advantage of:
- All critical 64-bit fixes documented and applied
- Headless-first design
- Comprehensive documentation

## Advanced: Cross-Compilation

To cross-compile from x86_64 Linux to ARM64:

```bash
# Install cross-compiler
sudo apt-get install gcc-aarch64-linux-gnu

# Edit mkfiles/mkfile-Linux-arm64:
CC=aarch64-linux-gnu-gcc -c
LD=aarch64-linux-gnu-gcc
AR=aarch64-linux-gnu-ar
```

## What's Next

With Linux ARM64 support, infernode can run on:
- NVIDIA Jetson (Orin, Xavier, Nano)
- Raspberry Pi 4/5 (64-bit mode)
- AWS Graviton instances
- Any ARM64 Linux system

## References

- `docs/LESSONS-LEARNED.md` - Critical fixes explained
- `docs/PORTING-ARM64.md` - Technical deep dive
- `build-linux-arm64.sh` - Build script

---

**Status:** Linux ARM64 files are in place. Ready for testing on actual hardware.
