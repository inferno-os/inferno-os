# NERV InferNode

[![CI](https://github.com/NERVsystems/infernode/actions/workflows/ci.yml/badge.svg)](https://github.com/NERVsystems/infernode/actions/workflows/ci.yml)
[![Security Analysis](https://github.com/NERVsystems/infernode/actions/workflows/security.yml/badge.svg)](https://github.com/NERVsystems/infernode/actions/workflows/security.yml)
[![OSSF Scorecard](https://github.com/NERVsystems/infernode/actions/workflows/scorecard.yml/badge.svg)](https://github.com/NERVsystems/infernode/actions/workflows/scorecard.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/NERVsystems/infernode/badge)](https://scorecard.dev/viewer/?uri=github.com/NERVsystems/infernode)

**64-bit Inferno® OS for embedded systems, servers, and AI agents**

InferNode is a lightweight Inferno® OS designed for modern 64-bit systems. Built for efficiency and minimal resource usage, it provides a complete Plan 9-inspired operating environment. A portable GUI (Xenith) may be compiled in, if desired.

## Features

- **Lightweight:** 15-30 MB RAM, 2-second startup
- **Headless:** Console-only operation, no X11 dependency
- **Complete:** 630+ utilities, full shell environment
- **Networked:** TCP/IP stack, 9P filesystem protocol
- **Portable:** Host filesystem access via Plan 9 namespace

## Quick Start

```bash
# Linux x86_64 (Intel/AMD)
./build-linux-amd64.sh
./emu/Linux/o.emu -r.

# Linux ARM64 (Jetson, Raspberry Pi, etc.)
./build-linux-arm64.sh
./emu/Linux/o.emu -r.

# macOS ARM64 (Apple Silicon)
./emu/MacOSX/o.emu -r.
```

The `-r.` option tells the emulator to use the current directory as the Inferno root filesystem (the path is concatenated directly to `-r` with no space). This lets you run directly from the source tree without installing.

You'll see the `;` prompt:

```
; ls /dis
; pwd
; date
```

See [QUICKSTART.md](QUICKSTART.md) for details.

## GUI Support (Optional)

InferNode supports an **optional SDL3 GUI backend** with **Xenith** as the default graphical interface.

### Xenith - AI-Native Text Environment

Xenith is an Acme fork optimized for AI agents and AI-human collaboration:

- **9P Filesystem Interface** - Agents interact via file operations, no SDK needed
- **Namespace Security** - Capability-based containment for AI agents
- **Observable** - All agent activity visible to humans
- **Multimodal** - Text and images in the same environment
- **Dark Mode** - Modern theming (Catppuccin) with full customization

See [docs/XENITH.md](docs/XENITH.md) for details.

### UI Improvements

Xenith addresses several usability issues in traditional Acme:

- **Async File I/O** - Text files, images, directories, and saves run in background threads
- **Non-Blocking UI** - UI remains responsive during file operations
- **Progressive Display** - Text appears incrementally; images show "Loading..." indicator
- **Buffered Channels** - Non-blocking sends prevent deadlocks during nested event loops
- **Unicode Input** - UTF-8 text entry with Plan 9 latin1 composition (e.g., `a'` → `á`)
- **Keyboard Handling** - Ctrl+letter support, macOS integration, compose sequences

Classic Acme freezes during file operations. On high-latency connections (remote 9P mounts, slow storage) or with large files, this blocks all interaction. The async architecture allows users to open windows, switch focus, or cancel operations while background tasks run.

### Building with GUI

```bash
# Install SDL3 (macOS)
brew install sdl3 sdl3_ttf

# Build with GUI support
cd emu/MacOSX
mk GUIBACK=sdl3 o.emu

# Run Xenith (AI-native interface)
./o.emu -r../.. xenith

# Run Acme (traditional)
./o.emu -r../.. acme

# Run window manager
./o.emu -r../.. wm/wm
```

**Features:**
- Cross-platform (macOS Metal, Linux Vulkan, Windows D3D)
- GPU-accelerated rendering
- High-DPI support (Retina displays)
- Zero overhead when GUI not used

**Default is headless** (no SDL dependency). See [docs/SDL3-GUI-PLAN.md](docs/SDL3-GUI-PLAN.md) for details.

## Veltro - AI Agent System

Veltro is an AI agent that operates within InferNode's namespace. The namespace IS the capability set — if a tool isn't mounted, it doesn't exist. The caller controls what tools and paths the agent can access.

### Quick Start

```bash
# Inside Inferno (terminal or Xenith)
mount -A tcp!127.0.0.1!5640 /n/llm       # Mount LLM provider
tools9p read list find search exec &       # Start tool server with chosen tools
veltro "list the files in /appl"           # Single-shot task
repl                                       # Interactive REPL
```

### Single-Shot Mode (`veltro`)

Runs a task to completion and exits. The agent queries the LLM, invokes tools, feeds results back, and repeats until done.

```
veltro [-v] [-n maxsteps] "task description"
```

### Interactive REPL (`repl`)

Conversational agent sessions with ongoing context. Runs in two modes:

- **Xenith mode** (automatic when Xenith is running) — Window with tag buttons: `Send` `Clear` `Reset` `Delete`. Read-only transcript above, user input below.
- **Terminal mode** (fallback) — Line-oriented stdin/stdout with `veltro>` prompt. Commands: `/reset`, `/quit`.

```
repl [-v] [-n maxsteps]
```

### Architecture

```
Caller                    Agent
  |                         |
  |-- tools9p (grants) ---> /tool/read, /tool/exec, ...
  |-- mount llm9p --------> /n/llm/
  |-- veltro "task" ------> queries LLM, invokes tools, loops
  |                         |
  |                    spawn subagent (NEWNS isolation)
  |                         |-- own LLM session
  |                         |-- subset of tools
```

- **tools9p** serves tools as a 9P filesystem at `/tool`. Each tool (read, list, find, search, write, edit, exec, spawn, etc.) is a loadable Limbo module.
- **Subagents** created via the `spawn` tool run in isolated namespaces (`pctl(NEWNS)`) with only the tools and paths the parent grants.
- **Security** flows caller-to-callee: the agent cannot self-grant capabilities.

See `appl/veltro/SECURITY.md` for the full security model.

## GoDis — Go-to-Dis Compiler (Preliminary)

GoDis compiles Go source code to Dis bytecode, allowing Go programs to run on Inferno's virtual machine alongside native Limbo programs. It exploits the shared Bell Labs lineage between Go and Limbo — goroutines map to `SPAWN`, channels to `NEWC`/`SEND`/`RECV`, and `select` to `ALT` — making compiled Go programs first-class Dis citizens that can share channels with Limbo code and participate in Inferno's namespace and security model.

```bash
cd tools/godis

# Compile a Go program to Dis bytecode
go run ./cmd/godis/ testdata/hello.go

# Run it on the Inferno emulator (from project root)
./emu/Linux/o.emu -r. /tools/godis/hello.dis
```

### What Works

- **Core language** — variables, constants, loops, conditionals, functions, methods, multiple returns, recursion
- **Data structures** — slices, maps, structs (nested/embedded), strings, pointers, heap allocation
- **Concurrency** — goroutines, channels (buffered/unbuffered/directional), select, close, for-range over channels
- **Advanced features** — closures, higher-order functions, defer, panic/recover, interfaces (type assertion, type switch), generics
- **Standard library** — `fmt`, `strings`, `strconv`, `math`, `errors`, `sort`, `sync`, `time`, `log`, `io` (intercepted and inlined as Dis instruction sequences)
- **Inferno integration** — `inferno/sys` package provides direct access to Sys module functions (open, read, write, bind, pipe, pctl, etc.)
- **Multi-package** — local package imports with transitive dependency resolution, compiled into a single `.dis` file
- **172+ test programs** passing end-to-end on the Dis VM

### Known Limitations

No reflection, no cgo, no full standard library — stdlib calls are intercepted and inlined. Maps use sorted arrays rather than hash tables. Single-binary output (no separate compilation).

See [tools/godis/README.md](tools/godis/README.md) for the full compiler architecture, translation strategy, and bug log.

## Use Cases

- **Embedded Systems** - Minimal footprint (10-20 MB)
- **Server Applications** - Lightweight, efficient
- **AI Agents** - Namespace-isolated agents with capability-based security
- **Development** - Fast Limbo compilation and testing; Go programs via GoDis
- **9P Services** - Filesystem export/import over network

## What's Inside

- **Shell** - Interactive command environment
- **630+ Utilities** - Standard Unix-like tools
- **Limbo Compiler** - Fast compilation of Limbo programs
- **Go-to-Dis Compiler** - Compile Go programs to Dis bytecode (preliminary)
- **9P Protocol** - Distributed filesystem support
- **Namespace Management** - Plan 9 style bind/mount
- **TCP/IP Stack** - Full networking capabilities

## Performance

- **Memory:** 15-30 MB typical usage
- **Startup:** 2 seconds cold start
- **CPU:** 0-1% idle, efficient under load
- **Footprint:** 1 MB emulator + 10 MB runtime

See [docs/PERFORMANCE-SPECS.md](docs/PERFORMANCE-SPECS.md) for benchmarks.

## Platforms

All platforms support the Dis interpreter and JIT compiler. Run with `emu -c1` to enable JIT (translates Dis bytecode to native code at module load time).

| Platform | CPU | JIT Speedup | Notes |
|----------|-----|-------------|-------|
| AMD64 Linux | AMD Ryzen 7 H 255 | **14.2x** | Containers, servers, workstations |
| ARM64 macOS | Apple M4 | **9.6x** | SDL3 GUI with Metal acceleration |
| ARM64 Linux | Cortex-A78AE (Jetson) | **8.3x** | Jetson AGX, Raspberry Pi 4/5 |

Speedups are v1 suite (6 benchmarks, best-of-3). Category highlights (AMD64, v2 suite): 36x branch/control, 20x integer arithmetic, 22x memory access, 15x mixed workloads.

Cross-language benchmarks (C, Java, Limbo) in `benchmarks/`. Full data in [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Documentation

- [docs/USER-MANUAL.md](docs/USER-MANUAL.md) - **Comprehensive user guide** (namespaces, devices, host integration)
- [QUICKSTART.md](QUICKSTART.md) - Getting started in 3 commands
- [docs/XENITH.md](docs/XENITH.md) - Xenith text environment for AI agents
- [appl/veltro/SECURITY.md](appl/veltro/SECURITY.md) - Veltro agent security model
- [tools/godis/README.md](tools/godis/README.md) - GoDis compiler architecture and translation strategy
- [docs/PERFORMANCE-SPECS.md](docs/PERFORMANCE-SPECS.md) - Performance benchmarks
- [docs/DIFFERENCES-FROM-STANDARD-INFERNO.md](docs/DIFFERENCES-FROM-STANDARD-INFERNO.md) - How InferNode differs
- [formal-verification/README.md](formal-verification/README.md) - Formal verification (TLA+, SPIN, CBMC)
- [docs/DOCUMENTATION-INDEX.md](docs/DOCUMENTATION-INDEX.md) - Complete documentation index

## Building

```bash
# Linux x86_64 (Intel/AMD)
./build-linux-amd64.sh

# Linux ARM64
./build-linux-arm64.sh

# macOS ARM64
export PATH="$PWD/MacOSX/arm64/bin:$PATH"
mk install
```

## Development Status

### Working

- **Dis Virtual Machine** - Interpreter and JIT compiler on all platforms. See `docs/arm64-jit/`.
- **GoDis Compiler** - Preliminary Go-to-Dis compiler; 172+ test programs passing. See `tools/godis/`.
- **SDL3 GUI Backend** - Cross-platform graphics with Metal/Vulkan/D3D
- **Xenith** - AI-native text environment with async I/O
- **Veltro** - AI agent system with namespace-based security, interactive REPL, and sub-agent spawning
- **Modern Cryptography** - Ed25519 signatures, updated certificate generation and authentication
- **Limbo Test Framework** - Unit testing with clickable error addresses
- **All 630+ utilities** - Shell, networking, filesystems, development tools
- **GitHub Actions CI** - Build verification, security scanning, supply chain scorecard

### Roadmap

- Linux ARM64 SDL3 GUI support
- Windows port

## About

InferNode is a GPL-free Inferno® OS distribution developed by NERV Systems, focused on headless operation and modern 64-bit platforms. It provides a complete Inferno® OS environment optimized for embedded systems, servers, and AI agent applications. InferNode's namespace model provides a capability-based security architecture well-suited for AI agent isolation.

Inspired by the concept of standalone Inferno® environments, InferNode builds on the MIT-licensed Inferno® OS codebase to deliver a lightweight, headless-capable system.

## License

MIT License (as per original Inferno® OS).

---

**NERV InferNode** - Lightweight Inferno® OS for ARM64 and AMD64

<sub>Inferno® is a distributed operating system, originally developed at Bell Labs, but now maintained by trademark owner Vita Nuova®.</sub>
