# Xenith Image Loading Implementation

## Status: Complete

**Updated:** 2026-01-30
**Branch:** feature/xenith-concurrency-overhaul

## What Was Implemented

### Core Functionality
- **Image display in Xenith windows** via `echo 'image /path' > /mnt/xenith/<id>/ctl`
- **PPM format support** (P3 ASCII, P6 binary) with subsampling for large images
- **JPEG format support** via Inferno's `readjpg` module (baseline sequential JFIF)
- **PNG format support** including:
  - Standard PNG via Inferno's `readpng` module (all bit depths: 1/2/4/8/16-bit)
  - Custom streaming decoder with subsampling (for large 8-bit images)
  - Adam7 interlaced PNG support
  - Progressive loading with visual feedback during decode

### Async I/O Architecture
- **Non-blocking image loading** - UI remains responsive during file read and decode
- **Spawned decode task** - Image decoding runs in a separate Limbo thread
- **Progressive updates** - Partial images displayed during decode (infrastructure in place)
- **Cancellation support** - Window close cancels in-progress loads
- **Buffered channels** - 64-slot casync buffer with non-blocking sends

### Memory Management
- Automatic subsampling for images exceeding 16 megapixels
- Stricter 8 megapixel limit for interlaced PNGs (require full image buffer)
- Streaming row-by-row processing to minimize memory footprint

### Files Modified
- `appl/xenith/imgload.b` - Core image loading: format dispatch, JPEG, PPM
- `appl/xenith/imgload.m` - Module interface (ImgProgress, readimagedataprogressive)
- `appl/xenith/pngload.b` - PNG-specific decoding: streaming, subsampling, Adam7
- `appl/xenith/pngload.m` - PNG loader module interface
- `appl/xenith/render/imgrender.b` - Renderer wrapper (PNG, JPEG, PPM magic detection)
- `appl/xenith/asyncio.b` - Async task management (imagetask, decodetask)
- `appl/xenith/asyncio.m` - Async message types (ImageData, ImageDecoded, ImageProgress)
- `appl/xenith/wind.b` - Image display and scaling
- `appl/xenith/xfid.b` - 9P file system integration
- `appl/xenith/dat.m` - Data structures
- `appl/xenith/xenith.b` - Main event loop handlers

## Current Limitations

### 1. Performance
**PNG decode speed is limited by interpreted Limbo bytecode.**

Root cause: Both `inflate.b` (zlib decompression) and PNG filter
application are implemented in **interpreted Limbo/Dis bytecode**, not native C.

For comparison:
- macOS native libpng: Opens 534MP image quickly (SIMD, native code)
- Xenith/Limbo: Large images take longer (interpreted bytecode)

The bottlenecks are:
1. `appl/lib/inflate.b` - 820 lines of Limbo implementing zlib decompression
2. PNG filter loops in `imgload.b` - Process every byte of every row

**Mitigations implemented:**
- Async loading keeps UI responsive during decode
- Progressive loading provides visual feedback (see IDEAS.md for testing)
- Subsampling reduces work for very large images

### 2. Large Image Handling
For very large images (e.g., 20800x25675 interlaced PNG, 534 megapixels):
- Subsampled to ~2311x2852 (factor 9) to fit memory
- Still requires decompressing all pixels through interpreted code
- Loading shown in tag line ("Loading...") while decode runs in background

## Optimizations Made

1. **Output loop optimization** - Iterate destination pixels (~2300) instead of
   source pixels (~20800) for interlaced images. Reduces loop iterations ~9x.

2. **Early dimension check** - Read PNG header before attempting full decode
   to fail fast on oversized images.

3. **Streaming decoder** - Process rows as they decompress rather than
   loading entire image into memory.

## Architecture

### Async Image Loading Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Main Thread (mousetask)                        │
│  ┌─────────────┐                                    ┌─────────────┐     │
│  │   xfid.b    │──── asyncloadimage() ────────────▶│ alt casync  │     │
│  │ (9P ctl)    │                                    │ (handlers)  │     │
│  └─────────────┘                                    └──────┬──────┘     │
│        │                                                   │            │
│        │ returns immediately                               │            │
│        ▼                                                   ▼            │
│  UI remains responsive              ImageData ──▶ spawn decodetask()   │
│                                     ImageDecoded ──▶ w.drawimage()     │
│                                     ImageProgress ──▶ w.drawimage()    │
└─────────────────────────────────────────────────────────────────────────┘
                                                             │
┌────────────────────────────────────────────────────────────┼────────────┐
│                        Background Threads                  │            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │            │
│  │  imagetask  │───▶│ decodetask  │───▶│progressfwd  │────┘            │
│  │ (file read) │    │ (PNG decode)│    │ (optional)  │                 │
│  └─────────────┘    └─────────────┘    └─────────────┘                 │
│        │                   │                                            │
│        ▼                   ▼                                            │
│  ┌─────────────┐    ┌─────────────┐                                    │
│  │ sys->read() │    │ imgload.b   │ format dispatch, JPEG, PPM         │
│  │ (I/O bound) │    │ pngload.b   │ PNG streaming/subsample            │
│  └─────────────┘    │ inflate.b   │ zlib decompression                 │
│                     │ readjpg.b   │ JPEG baseline decode               │
│                     │ (CPU bound) │                                    │
│                     └─────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Design Points

1. **Non-blocking sends**: All async tasks use retry loops to avoid deadlock
2. **Buffered channels**: casync has 64 slots to absorb bursts during nested event loops
3. **Cancellation**: Window close triggers op.ctl send, tasks check and exit
4. **Progress forwarding**: Separate thread prevents decode stalls on channel full

The Draw system is native C. The performance bottleneck is inflate.b (zlib in Limbo).

## Completed Work

### Async/Background Loading (Done)
Image loading is now non-blocking:
- File reads run in spawned `imagetask()`
- Decode runs in spawned `decodetask()`
- Progress updates via `progressforwarder()` (infrastructure in place)
- Cancellation support via `AsyncOp.ctl` channel
- "Loading..." indicator in window tag during load

### Deadlock Prevention (Done)
Fixed producer-consumer deadlock during window drag operations:
- Increased casync buffer from 8 to 64 slots
- All async tasks use non-blocking sends with retry loops
- Nested event loops (dragwin, scroll) no longer block async tasks

## Remaining Work

### Priority 1: Native zlib Implementation
Replace `appl/lib/inflate.b` with native C code in the emu. This would:
- Speed up PNG and all compression operations
- Benefit the entire system, not just image loading
- Require changes to `emu/port/` or `libinterp/`

### Priority 2: ARM64 JIT Compiler
Would improve all Limbo performance including image decode:
- `libinterp/comp-arm64.c` is currently a stub
- See IDEAS.md for implementation notes

### Priority 3: Native PNG Decoder (Alternative)
If native zlib is too complex, add a dedicated native PNG module:
- C implementation using libpng or custom code
- Takes path, returns Draw->Image
- Bypasses Limbo entirely for image decode

### Priority 4: Format Optimization
- JPEG support added (baseline sequential via readjpg)
- Consider adding GIF support (readgif exists in appl/lib/)
- Native Inferno image format is already fast (no compression)
- Pre-convert large PNGs to uncompressed format for faster loading

## Testing

### Verified Working
- Small non-interlaced PNG: ✓
- Small interlaced PNG (200x200 RGBA): ✓
- PPM format: ✓
- JPEG (baseline sequential): needs testing
- PNG non-8-bit depths (1/2/4/16-bit): needs testing (now falls back to system reader)
- Async loading (UI responsive during load): ✓
- Window close during load (cancellation): ✓
- Concurrent window drag + image load: ✓

### Progressive Loading Test
Progressive loading infrastructure is in place but imperceptible on fast local storage.
See IDEAS.md "TODO: Progressive Image Loading Test" for verification procedure using
artificial delays.

### Test Commands
```sh
# Start Xenith
cd /Users/pdfinn/github.com/NERVsystems/infernode/emu/MacOSX
./o.emu -r../.. sh -l -c 'xenith -t dark'

# Load test image (in Xenith)
echo 'image /n/local/tmp/test-rgba-interlaced.png' > /mnt/xenith/1/ctl

# Test async loading - try clicking "New" while image loads
# UI should remain responsive

# Clear image
echo 'clearimage' > /mnt/xenith/1/ctl
```

## Commits

### Original Image Support
1. `c85c03a` - feat(xenith): Add portable streaming PNG/PPM image loading with subsampling
2. `b4ae02a` - feat(xenith): Add Adam7 interlaced PNG support for large images
3. `8136dd4` - fix(xenith): Increase subsample factor for interlaced PNGs to fit heap
4. `11e117d` - perf(xenith): Optimize interlaced PNG output loop

### Async Loading (2026-01)
5. `c0d5661e` - feat(xenith): Implement async image loading with spawned decode task
6. Various commits - Deadlock fixes, progressive loading infrastructure

## References

- PNG Specification: http://www.libpng.org/pub/png/spec/
- Adam7 Interlacing: https://en.wikipedia.org/wiki/Adam7_algorithm
- Inferno Filter module: `/module/filter.m`
- Inferno Draw module: `/module/draw.m`
