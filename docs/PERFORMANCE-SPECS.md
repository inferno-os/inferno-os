# InferNode - Performance Specifications

**Platforms:** x86_64 Linux, ARM64 Linux, ARM64 macOS
**Build:** Headless (no X11/graphics)

## Binary Sizes

### Core Binaries

| Binary | x86_64 Linux | ARM64 macOS | Notes |
|--------|-------------|-------------|-------|
| Emulator (`o.emu`) | 3.3 MB | 1.0 MB | x86_64 code is larger |
| Limbo Compiler | 1.0 MB | 376 KB | |
| mk Build Tool | 314 KB | ~100 KB | |

### ARM64 macOS (reference)
- **Emulator** (`emu/MacOSX/o.emu`): 1.0 MB
- **Limbo Compiler** (`MacOSX/arm64/bin/limbo`): 376 KB
- **mk Build Tool** (`MacOSX/arm64/bin/mk`): ~100 KB

### x86_64 Linux
- **Emulator** (`emu/Linux/o.emu`): 3.3 MB
- **Limbo Compiler** (`Linux/amd64/bin/limbo`): 1.0 MB
- **mk Build Tool** (`Linux/amd64/bin/mk`): 314 KB

### Libraries (C)
- **libinterp.a** (Dis VM): 921 KB
- **libdraw.a** (Graphics): 387 KB
- **libmath.a** (Math): 300 KB
- **libmemdraw.a**: 240 KB
- **lib9.a** (Core): 167 KB
- **Total libraries**: ~2.5 MB

### Compiled Code
- **Compiled ARM64 code**: 5.5 MB
- **Limbo .dis files**: 2.2 MB (280+ programs)
- **Limbo source**: 15 MB (appl/)

## Runtime Performance

### Startup Time
- **Cold start to prompt**: ~2 seconds
- **Includes:**
  - Emulator initialization
  - Dis VM startup
  - emuinit.dis load and execution
  - Shell (sh.dis) load
  - Profile execution (mntgen, trfs servers)

### Memory Usage

**Idle (shell prompt):**
- **RSS (Resident)**: ~15-20 MB
- **VSZ (Virtual)**: ~4.1 GB (mostly virtual, not actual RAM)
- **Actual RAM used**: ~15-20 MB

**With active work:**
- **Light use** (few commands): ~20-30 MB
- **Moderate use** (multiple utilities): ~30-50 MB
- **Heavy use** (many concurrent programs): ~50-100 MB

**Memory efficient:** Typical usage under 30 MB RAM.

### CPU Usage

**Idle:**
- **0-1% CPU** - Minimal when waiting at prompt

**Active:**
- **Variable** - Depends on workload
- Text processing: 5-15% CPU
- Compilation: 20-40% CPU
- Network operations: 5-20% CPU

**Single-threaded** - Uses one core efficiently

### Disk Usage

**Minimal Installation:**
- **Binaries only**: ~8 MB (emulator + tools)
- **With libraries**: ~10 MB
- **Complete** (source + binaries + docs): ~68 MB

**Runtime:**
- **Read-only** for most operations
- **Writes** only to:
  - /usr/username (home)
  - /tmp
  - Explicitly written files

## Performance Characteristics

### Startup
- **Fast:** 2-second cold start
- **Consistent:** No variance
- **Light:** Minimal resource impact

### Shell Performance
- **Command execution**: Instant (<10ms)
- **File operations**: Native speed
- **Process creation**: Fast (~5-10ms)

### Networking
- **TCP connections**: Standard latency
- **9P operations**: Efficient (protocol designed for this)
- **Host filesystem** (via trfs): Slight overhead vs native

### Compilation (Limbo)
- **Small program** (~100 lines): <100ms
- **Medium program** (~1000 lines): <500ms
- **Large program** (~5000 lines): ~1-2 seconds

**Fast compilation** - Limbo compiler is efficient.

## Scalability

### Concurrent Programs
- **Limited by memory** - Each Dis program ~1-5 MB
- **Tested:** 10-20 concurrent programs work fine
- **Theoretical:** Hundreds possible (VM designed for this)

### File Operations
- **No limits** beyond host filesystem
- **9P efficient** for many small files
- **Host filesystem** access at native speeds

### Network Connections
- **Limited by OS** (typical: thousands of connections)
- **9P servers** handle multiple clients efficiently
- **Tested:** Multiple concurrent connections work

## Comparison with Other Systems

### vs Standard Inferno OS
- **Smaller:** No GUI (saves ~10-20 MB)
- **Faster startup:** No graphics init
- **Same performance:** Core VM identical
- **More efficient:** Headless reduces overhead

### vs Full Desktop OS
- **Tiny:** 10-20 MB RAM vs 1-2 GB
- **Fast:** 2s startup vs 30-60s
- **Focused:** Does one thing well
- **Embedded-friendly:** Minimal footprint

### vs Docker Container
- **Comparable size:** Similar footprint
- **Faster startup:** No container overhead
- **Native:** Runs directly on macOS
- **Simpler:** No container runtime needed

## Resource Requirements

### Minimum
- **RAM:** 32 MB (theoretical minimum)
- **Disk:** 10 MB (binaries only)
- **CPU:** Any 64-bit processor (x86_64 or ARM64)
- **OS:** Linux (glibc) or macOS 11+

### Recommended
- **RAM:** 64 MB+ (comfortable headroom)
- **Disk:** 100 MB (with source and docs)
- **CPU:** Modern x86_64 or ARM64
- **OS:** Linux with glibc, or macOS 13+

### Tested On
- **x86_64 Linux** - Intel/AMD processors, containers
- **ARM64 Linux** - Jetson, Raspberry Pi
- **Apple M1/M2/M3** - Excellent performance
- **macOS 13-15** - Fully compatible
- **RAM:** 8-64 GB (uses minimal fraction)

## Performance Optimizations

### What We Use
- **Pool allocator** with 64-bit quanta (127)
- **Direct system calls** (no abstraction overhead)
- **Efficient bytecode** (Dis VM)
- **Minimal dependencies** (no bloat)

### What Could Be Added
- **JIT compiler** (inferno64 has this for amd64)
- **Thread pooling** (currently creates threads on demand)
- **Memory pool tuning** (could adjust quanta/sizes)
- **Disk caching** (currently minimal)

## Benchmarks (Informal)

**Tested on Apple M1 Pro, 16GB RAM:**

| Operation | Time | Notes |
|-----------|------|-------|
| Startup | 2s | Cold start to prompt |
| Compile hello.b | 50ms | Simple program |
| ls /dis (157 files) | 20ms | Directory listing |
| grep pattern *.b | 100ms | Text search |
| TCP connect | 5ms | To localhost |
| 9P export | 10ms | Start server |

**Observations:**
- Very responsive
- No noticeable lag
- Suitable for interactive use
- Good for automation

## Suitability

### Excellent For:
- **Embedded systems** - Small footprint
- **Servers** - Low resource usage
- **Automation** - Fast startup, minimal overhead
- **Development** - Quick iteration
- **AI agents** - Lightweight, scriptable

### Not Optimal For:
- **Heavy computation** (use native code)
- **Large datasets** (memory-bound)
- **Graphics** (headless build)
- **High-throughput** (single-threaded)

## Resource Monitoring

**To check while running:**
```bash
# Start InferNode
./emu/MacOSX/o.emu -r. &
EMUPID=$!

# Check memory
ps -p $EMUPID -o rss,vsz,pcpu,command

# Monitor continuously
top -pid $EMUPID
```

**Typical output:**
```
RSS: 15-30 MB (actual RAM)
VSZ: 4GB (virtual, mostly unmapped)
CPU: 0-1% (idle) to 20-40% (active)
```

## Disk I/O

**Read-mostly workload:**
- Binaries loaded once
- .dis files cached
- Minimal write operations

**Write operations:**
- User home directory
- /tmp files
- Explicitly created files
- Host filesystem via trfs

**No heavy disk I/O** unless explicitly requested.

## Network Performance

**TCP/IP:**
- Standard BSD socket performance
- No additional overhead
- Tested: 100+ Mbps easily handled

**9P Protocol:**
- Efficient for filesystem operations
- Low latency (designed for Plan 9)
- Good for distributed filesystems

## Tuning Options

**Memory pools** (emu/port/alloc.c):
```c
{ "main",  0, 32*1024*1024, 127, 512*1024, 0, 31*1024*1024 },
```
- maxsize: 32 MB (can increase)
- quanta: 127 (optimal for 64-bit)
- ressize: 512 KB (initial)

**Adjust for specific workloads** if needed.

## Summary

**InferNode is:**
- **Lightweight:** 15-30 MB typical RAM usage
- **Fast:** 2-second startup
- **Efficient:** Low CPU when idle
- **Compact:** 1-3.3 MB emulator, 10-68 MB total
- **Scalable:** Handles concurrent workloads well
- **Portable:** Runs on x86_64 and ARM64

**Perfect for:**
- Embedded systems
- Server applications
- AI/automation agents
- Development environments
- Resource-constrained deployments
- Containers and cloud instances

---

**Performance verified on x86_64 Linux, ARM64 Linux, and Apple Silicon (M1/M2/M3) running macOS 13-15.**
