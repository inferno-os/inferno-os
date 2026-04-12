# InferNode

[![CI](https://github.com/infernode-os/infernode/actions/workflows/ci.yml/badge.svg)](https://github.com/infernode-os/infernode/actions/workflows/ci.yml)
[![Security Analysis](https://github.com/infernode-os/infernode/actions/workflows/security.yml/badge.svg)](https://github.com/infernode-os/infernode/actions/workflows/security.yml)
[![OSSF Scorecard](https://github.com/infernode-os/infernode/actions/workflows/scorecard.yml/badge.svg)](https://github.com/infernode-os/infernode/actions/workflows/scorecard.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/infernode-os/infernode/badge)](https://scorecard.dev/viewer/?uri=github.com/infernode-os/infernode)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/12422/badge)](https://www.bestpractices.dev/projects/12422)

**64-bit Inferno® OS for embedded systems, servers, and AI agents**

InferNode is a modern Inferno® OS distribution designed for 64-bit systems. It provides a complete Plan 9-inspired operating environment with JIT compilation, namespace-based security, and an AI agent system — all in under 30 MB of RAM. A portable GUI (Xenith) may be compiled in, if desired.

## Features

- **Lightweight:** 15-30 MB RAM, 2-second startup, ~10 MB on disk
- **JIT Compiled:** Native code generation on AMD64 (14x) and ARM64 (9x) — interpreter fallback everywhere
- **AI Agents:** Namespace-isolated agents with 39 tool modules, LLM integration via 9P (Veltro)
- **Payments:** Native cryptocurrency wallet with x402 payment protocol, ERC-20 tokens, and budget-enforced agent spending (**experimental — testnet only**)
- **Complete:** 800+ Limbo source files, 815 compiled utilities, full shell environment
- **GUI:** Three-zone tiling GUI (Lucia), AI-native text editor (Xenith), login screen with secstore authentication
- **Networked:** TCP/IP stack, 9P filesystem protocol, distributed namespaces
- **Formally Verified:** Namespace isolation proven via TLA+, SPIN, and CBMC
- **Headless by Default:** No GUI dependency; optional SDL3 with Metal/Vulkan/D3D

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

```powershell
# Windows x86_64 (from x64 Native Tools Command Prompt)
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1
.\emu\Nt\o.emu.exe -r .
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

- **9P Filesystem Interface** — Agents interact via file operations, no SDK needed
- **Namespace Security** — Capability-based containment for AI agents
- **Observable** — All agent activity visible to humans
- **Multimodal** — Text and images in the same environment
- **Dark Mode** — Modern theming (Catppuccin) with full customization

See [docs/XENITH.md](docs/XENITH.md) for details.

### Lucia - Three-Zone Tiling GUI

Lucia is the primary GUI for AI-human collaboration, organizing the workspace into three zones:

- **Conversation** — Chat interface with streaming LLM responses and tool-call activity tiles
- **Presentation** — Rich content display (artifacts, code, diagrams, images)
- **Context** — Tool toggles, namespace path management, and activity tracking

Features include live theme sync across all apps, HiDPI antialiased fonts, and a comprehensive test suite (80+ unit tests for the UI server).

### UI Improvements

Xenith replaces classic Acme's blocking I/O with an async architecture:

- **Async File I/O** — Text, images, directories, and saves run in background threads
- **Non-Blocking UI** — Remains responsive during file operations and on high-latency 9P mounts
- **Unicode Input** — UTF-8 text entry with Plan 9 latin1 composition (e.g., `a'` → `á`)
- **HiDPI Fonts** — Antialiased combined fonts replace bitmap fonts for sharp text on Retina/HiDPI displays

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

```powershell
# Windows x86_64 (from x64 Native Tools Command Prompt)
# Download SDL3-devel-*-VC.zip from https://github.com/libsdl-org/SDL/releases
# Extract to SDL3-dev/ in the project root
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1   # build libraries first
powershell -ExecutionPolicy Bypass -File build-windows-sdl3.ps1    # build GUI emulator

# Run Xenith
.\emu\Nt\o.emu.exe -g 1024x768 -r . sh -l -c xenith

# Run window manager
.\emu\Nt\o.emu.exe -g 1024x768 -r . wm/wm
```

**Features:**
- Cross-platform (macOS Metal, Linux Vulkan, Windows D3D)
- GPU-accelerated rendering
- High-DPI support (Retina displays)
- Zero overhead when GUI not used

**Default is headless** (no SDL dependency). See [docs/SDL3-GUI-PLAN.md](docs/SDL3-GUI-PLAN.md) for details.

## Veltro - AI Agent System

Veltro is an AI agent system that operates within InferNode's namespace. The namespace IS the capability set — if a tool isn't mounted, it doesn't exist. The caller controls what tools and paths the agent can access.

### Quick Start

```bash
# Inside Inferno (terminal or Xenith)
llmsrv &                                  # Start LLM service (self-mounts at /n/llm)
tools9p read list find search exec &       # Start tool server with chosen tools
veltro "list the files in /appl"           # Single-shot task
repl                                       # Interactive REPL
```

### Modes

- **Single-shot** (`veltro "task"`) — Runs a task to completion and exits. The agent queries the LLM, invokes tools, feeds results back, and repeats until done.
- **Interactive REPL** (`repl`) — Conversational agent sessions with ongoing context. Works in both Xenith (GUI with tag buttons) and terminal (line-oriented with `veltro>` prompt) modes.
- **Lucia** — Three-zone tiling GUI (Conversation | Presentation | Context) for AI-human collaboration. Includes activity tracking, tool toggles, and namespace path management with per-path read/write permissions.

### Key Components

- **llmsrv** — Exposes LLM providers (Anthropic API or Ollama/OpenAI-compatible) as a 9P filesystem at `/n/llm`. Agents read and write files to interact with the model — no SDK needed. Can also mount a remote llmsrv via 9P. Includes a fallback text tool-call parser for non-Anthropic models.
- **tools9p** — Serves 39 tool modules as a 9P filesystem at `/tool`. Each tool (read, list, find, search, write, edit, exec, spawn, shell, wallet, payfetch, vision, etc.) is a loadable Limbo module.
- **Subagents** — Created via the `spawn` tool, run in isolated namespaces (`pctl(NEWNS)`) with only the tools and paths the parent grants.
- **Security** — Flows caller-to-callee: the agent cannot self-grant capabilities. Namespace isolation formally verified with TLA+ and SPIN.

### Architecture

```
Caller                    Agent
  |                         |
  |-- tools9p (grants) ---> /tool/read, /tool/exec, ...
  |-- llmsrv ------------> /n/llm/
  |-- wallet9p ----------> /n/wallet/
  |-- veltro "task" ------> queries LLM, invokes tools, loops
  |                         |
  |                    spawn subagent (NEWNS isolation)
  |                         |-- own LLM session
  |                         |-- subset of tools
```

See `appl/veltro/SECURITY.md` for the full security model.

## Wallet & Payments (Experimental — Testnet Only)

> **WARNING:** The wallet system is under active development and has not been audited. Use only with testnets (Ethereum Sepolia, Base Sepolia). Do not store real funds or mainnet private keys.

InferNode includes a native cryptocurrency wallet system that enables agents to make autonomous, budget-controlled payments. Everything follows Plan 9 principles: wallet accounts are files, secrets live in factotum, and persistent storage uses secstore.

- **wallet9p** — 9P file server at `/n/wallet/` providing account creation, signing, balance queries, and payment execution
- **x402 protocol** — HTTP 402 payment flows with EIP-3009/EIP-712 authorization signing
- **payfetch tool** — HTTP client that automatically handles x402 payments when a server returns 402
- **Budget enforcement** — Server-side spending limits per transaction and per session; agents cannot bypass
- **Ethereum support** — secp256k1 ECDSA, Keccak-256, RLP encoding, EIP-155 transaction signing, ERC-20 token transfers
- **Key persistence** — All keys (wallet, API, credentials) stored in factotum, encrypted with AES-256-GCM via secstore, surviving restarts
- **Login screen** — Secstore authentication on boot with password confirmation, retry on failure, and headless mode via `$SECSTORE_PASSWORD`

Supported networks: Ethereum Mainnet, Ethereum Sepolia, Base, Base Sepolia.

See [docs/WALLET-AND-PAYMENTS.md](docs/WALLET-AND-PAYMENTS.md) for the full architecture and API reference.

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
- **190+ test programs** passing end-to-end on the Dis VM

### Known Limitations

No reflection, no cgo, no full standard library — stdlib calls are intercepted and inlined. Maps use sorted arrays rather than hash tables. Single-binary output (no separate compilation).

See [tools/godis/README.md](tools/godis/README.md) for the compiler architecture, translation strategy, and bug log.

## Use Cases

- **AI Agents** — Namespace-isolated agents with capability-based security, LLM integration via 9P
- **Embedded Systems** — Minimal footprint (~10 MB on disk, 15-30 MB RAM)
- **Server Applications** — Lightweight services with 9P filesystem export
- **Development** — Fast Limbo compilation and testing; Go programs via GoDis
- **Edge Computing** — ARM64 JIT on NVIDIA Jetson, Raspberry Pi

## What's Inside

- **Shell** — Interactive rc-style command environment
- **815 Utilities** — Standard tools compiled to Dis bytecode (the Inferno `/usr/bin`)
- **Limbo Compiler** — Fast compilation of Limbo programs
- **Go-to-Dis Compiler** — Compile Go programs to Dis bytecode (preliminary)
- **JIT Compilers** — AMD64 and ARM64 native code generation
- **9P Protocol** — Distributed filesystem support
- **Namespace Management** — Plan 9 style bind/mount with formal verification
- **TCP/IP Stack** — Full networking capabilities
- **Wallet & Payments** — Cryptocurrency wallet, x402 protocol, budget-enforced agent spending (**experimental — testnet only**)
- **Secstore & Factotum** — Encrypted key persistence with PAK authentication
- **Quantum-Safe Cryptography** — ML-KEM, ML-DSA, SLH-DSA (FIPS 203/204/205)
- **Text Editor** — Built-in editor with undo/redo, find & replace, 9P IPC for agent control
- **Web Browser** — Charon browser with CSS layout engine (block, inline-block, flex, grid)

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
| AMD64 Windows | Intel/AMD x86_64 | interpreter only | SDL3 GUI with D3D acceleration |

Speedups are v1 suite (6 benchmarks, best-of-3). Category highlights (AMD64, v2 suite): 36x branch/control, 20x integer arithmetic, 22x memory access, 15x mixed workloads.

Cross-language benchmarks (C, Java, Limbo) in `benchmarks/`. Full data in [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Documentation

- [docs/USER-MANUAL.md](docs/USER-MANUAL.md) — **Comprehensive user guide** (namespaces, devices, host integration)
- [QUICKSTART.md](QUICKSTART.md) — Getting started in 3 commands
- [RUN_TOUR.md](RUN_TOUR.md) — Interactive Veltro feature tour
- [docs/XENITH.md](docs/XENITH.md) — Xenith text environment for AI agents
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — System architecture and component diagram
- [docs/WALLET-AND-PAYMENTS.md](docs/WALLET-AND-PAYMENTS.md) — Wallet, x402 payments, secstore, and key management
- [appl/veltro/SECURITY.md](appl/veltro/SECURITY.md) — Veltro agent security model
- [tools/godis/README.md](tools/godis/README.md) — GoDis compiler architecture and translation strategy
- [docs/BENCHMARKS.md](docs/BENCHMARKS.md) — Cross-language JIT benchmarks (C, Java, Limbo)
- [docs/PERFORMANCE-SPECS.md](docs/PERFORMANCE-SPECS.md) — Performance specs and binary sizes
- [docs/WINDOWS-BUILD.md](docs/WINDOWS-BUILD.md) — Building and running on Windows
- [docs/DIFFERENCES-FROM-STANDARD-INFERNO.md](docs/DIFFERENCES-FROM-STANDARD-INFERNO.md) — How InferNode differs from standard Inferno
- [formal-verification/README.md](formal-verification/README.md) — Formal verification (TLA+, SPIN, CBMC)
- [docs/DOCUMENTATION-INDEX.md](docs/DOCUMENTATION-INDEX.md) — Complete documentation index (100+ docs)

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

```powershell
# Windows x86_64 (from x64 Native Tools Command Prompt)
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1
```

See [docs/WINDOWS-BUILD.md](docs/WINDOWS-BUILD.md) for detailed Windows instructions including SDL3 GUI setup.

## Development Status

### Working

- **Dis Virtual Machine** — Interpreter and JIT compiler on AMD64 and ARM64. See `docs/arm64-jit/`.
- **GoDis Compiler** — Preliminary Go-to-Dis compiler; 190+ test programs passing. See `tools/godis/`.
- **SDL3 GUI Backend** — Cross-platform graphics with Metal/Vulkan/D3D (macOS, Linux, Windows)
- **Xenith** — AI-native text environment with async I/O, dark mode, HiDPI fonts, image support
- **Lucia** — Three-zone tiling GUI with live theme sync, activity tracking, 80+ unit tests
- **Veltro** — AI agent system with namespace-based security, 39 tool modules, REPL, and sub-agent spawning
- **llmsrv** — LLM providers exposed as 9P filesystem (Anthropic + OpenAI-compatible)
- **Wallet & Payments** — Cryptocurrency wallet (wallet9p), x402 payment protocol, ERC-20 tokens, budget enforcement (**experimental — testnet only**)
- **Secstore & Factotum** — PAK-authenticated encrypted key persistence with secstore; login screen for boot-time unlock
- **Text Editor** — Undo/redo, find & replace, double/triple-click selection, 9P IPC for Veltro agent integration
- **Charon Browser** — CSS layout engine (block, inline-block, flex, grid), live theme support
- **Quantum-Safe Cryptography** — FIPS 203 (ML-KEM), FIPS 204 (ML-DSA), FIPS 205 (SLH-DSA)
- **Modern Cryptography** — Ed25519, secp256k1 ECDSA, Keccak-256, AES-256-GCM
- **Formal Verification** — Namespace isolation verified via TLA+ (3.17B states), SPIN, and CBMC
- **Limbo Test Framework** — 91 test files with clickable error addresses and CI integration
- **Windows AMD64 Port** — Headless and SDL3 GUI with Xenith, interpreter only (no JIT yet)
- **All 815 utilities** — Shell, networking, filesystems, development tools
- **GitHub Actions CI** — Build verification, security scanning (CodeQL + cppcheck), supply chain scorecard

### Roadmap

- Linux ARM64 SDL3 GUI support (backend 95% complete, build system integration remaining)
- Windows JIT compiler
- Lucia P0 fixes (app slot watchdog, voice FD leak, font nil guards) — see [docs/LUCIA-EVALUATION.md](docs/LUCIA-EVALUATION.md)

## Contributing

We welcome contributions — from security audits and 9P integrations to bug
fixes and documentation. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get
started, what the project needs most, and development workflow details.

## About

InferNode is a GPL-free Inferno® OS distribution. It extends the MIT-licensed Inferno® OS codebase with JIT compilers for AMD64 and ARM64, an AI agent system (Veltro) with formally verified namespace isolation, a cryptocurrency wallet with x402 payment protocol, quantum-safe cryptography, a Go-to-Dis compiler, and an optional SDL3 GUI (Lucia + Xenith). Designed for embedded systems, servers, and AI agent applications where lightweight footprint and capability-based security matter.

## License

MIT License (as per original Inferno® OS).

---

**InferNode** — Lightweight Inferno® OS for AMD64, ARM64, and Windows

<sub>Inferno® is a distributed operating system, originally developed at Bell Labs, but now maintained by trademark owner Vita Nuova®.</sub>
