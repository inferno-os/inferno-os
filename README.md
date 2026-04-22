# InferNode

[![Latest release](https://img.shields.io/github/v/release/infernode-os/infernode?display_name=tag)](https://github.com/infernode-os/infernode/releases/latest)
[![Container image](https://img.shields.io/badge/ghcr.io-infernode--os%2Finfernode-blue?logo=docker)](https://github.com/infernode-os/infernode/pkgs/container/infernode)
[![CI](https://github.com/infernode-os/infernode/actions/workflows/ci.yml/badge.svg)](https://github.com/infernode-os/infernode/actions/workflows/ci.yml)
[![Security Analysis](https://github.com/infernode-os/infernode/actions/workflows/security.yml/badge.svg)](https://github.com/infernode-os/infernode/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/infernode-os/infernode/badge)](https://scorecard.dev/viewer/?uri=github.com/infernode-os/infernode)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/12422/badge)](https://www.bestpractices.dev/projects/12422)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**64-bit Inferno® OS for embedded systems, servers, and AI agents.**

InferNode is a modern Inferno® distribution with JIT compilation on AMD64 (14×) and ARM64 (9×), namespace-isolated AI agents (Veltro), an optional SDL3 GUI (Lucia + Xenith), and a complete Plan 9-inspired environment — all in under 30 MB of RAM.

## Quick Start

### Install (recommended)

Every tagged release ships signed binaries for macOS and Linux on the [latest release page](https://github.com/infernode-os/infernode/releases/latest). No toolchain, no build step — download and run.

- **macOS (Apple Silicon)** — `infernode-*-macos-arm64.dmg`: open, drag to Applications, launch.
- **Linux x86_64 (GUI)** — `infernode-*-linux-amd64-gui.tar.gz`: SDL3 is bundled.
- **Linux ARM64 (GUI)** — `infernode-*-linux-arm64-gui.tar.gz`: for Jetson, Raspberry Pi, etc.
- **Linux (headless)** — `infernode-*-linux-amd64.tar.gz` or `infernode-*-linux-arm64.tar.gz`.
- **Container** — multi-arch (amd64 + arm64) headless image on GHCR:
  ```bash
  docker run -it ghcr.io/infernode-os/infernode:latest
  ```

```bash
tar xzf infernode-*-linux-*-gui.tar.gz
cd infernode-*-linux-*-gui
./infernode                   # or ./infernode-headless in the non-GUI tarballs
```

Every release asset is published with a cosign bundle (`.pem` + `.sig`) and a signed `SHA256SUMS.txt`; container images carry SLSA build provenance. See [Releases](https://github.com/infernode-os/infernode/releases) for the full history.

### Build from source

Prefer a release unless you need bleeding-edge `master` or a platform without a prebuilt binary.

**Linux (x86_64 or ARM64):**
```bash
git clone https://github.com/infernode-os/infernode.git
cd infernode
./install-sdl3.sh              # one-time, GUI only
./build-linux-amd64.sh         # or ./build-linux-arm64.sh
./run-lucia-linux.sh           # launch the GUI
```
Pass `headless` to the build script to skip SDL3. For a headless shell, run
`./emu/Linux/o.emu -c1 -r.` (the `;` prompt gives you a full Inferno® shell with 815 utilities).

**macOS (Apple Silicon):**
```bash
git clone https://github.com/infernode-os/infernode.git
cd infernode
./makemk.sh                    # bootstrap mk (one-time)
brew install sdl3 sdl3_ttf     # GUI only
./build-macos-sdl3.sh          # or ./build-macos-headless.sh
./run-lucia.sh                 # launch the GUI
```
For a headless shell, run `./emu/MacOSX/o.emu -c1 -r.`.

**Windows (x86_64)** — from an **x64 Native Tools Command Prompt**:
```powershell
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1
.\emu\Nt\o.emu.exe -r .
```
For the SDL3 GUI, see [docs/WINDOWS-BUILD.md](docs/WINDOWS-BUILD.md).

The `-c1` flag enables the JIT; `-r.` tells the emulator to use the current directory as the Inferno® root. See [QUICKSTART.md](QUICKSTART.md) and [docs/USER-MANUAL.md](docs/USER-MANUAL.md) for more.

## Highlights

- **Lightweight** — 15–30 MB RAM, 2-second startup, ~10 MB on disk.
- **JIT compiled** — native code generation on AMD64 and ARM64; interpreter fallback everywhere.
- **AI agents** — namespace-isolated [Veltro](appl/veltro/SECURITY.md) agents with 39 tool modules, LLM integration via 9P, and formally verified containment.
- **GUI (optional)** — three-zone tiling UI (Lucia) and an AI-native text environment ([Xenith](docs/XENITH.md)), rendered via SDL3 (Metal / Vulkan / D3D).
- **Payments** — native cryptocurrency wallet with [x402](docs/WALLET-AND-PAYMENTS.md) payment protocol, ERC-20 tokens, and budget-enforced agent spending. **Experimental — testnet only.**
- **Go on Dis** — the [GoDis compiler](tools/godis/README.md) translates Go source to Dis bytecode; 190+ test programs pass end-to-end.
- **Formally verified** — namespace isolation proven in TLA+ (3.17B states), SPIN, and CBMC.
- **Quantum-safe crypto** — ML-KEM, ML-DSA, SLH-DSA (FIPS 203/204/205).
- **Complete** — 800+ Limbo source files, a full shell, TCP/IP, 9P, and 815 compiled utilities.

## Platforms

Run with `emu -c1` to enable the JIT (Dis bytecode → native code at module load).

| Platform | CPU | JIT speedup | Notes |
|----------|-----|-------------|-------|
| Linux AMD64 | AMD Ryzen 7 H 255 | **14.2×** | Servers, containers, workstations |
| macOS ARM64 | Apple M4 | **9.6×** | SDL3 GUI with Metal |
| Linux ARM64 | Cortex-A78AE (Jetson) | **8.3×** | Jetson AGX, Raspberry Pi 4/5 |
| Windows AMD64 | Intel / AMD x86_64 | interpreter only | SDL3 GUI with D3D |

Speedups are v1 suite (6 benchmarks, best-of-3). Full data: [docs/BENCHMARKS.md](docs/BENCHMARKS.md). Performance envelope: [docs/PERFORMANCE-SPECS.md](docs/PERFORMANCE-SPECS.md).

## Documentation

- [QUICKSTART.md](QUICKSTART.md) — running in under a minute
- [docs/USER-MANUAL.md](docs/USER-MANUAL.md) — namespaces, devices, host integration
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system architecture
- [docs/XENITH.md](docs/XENITH.md) — AI-native text environment
- [docs/WALLET-AND-PAYMENTS.md](docs/WALLET-AND-PAYMENTS.md) — wallet, x402, secstore, key management
- [appl/veltro/SECURITY.md](appl/veltro/SECURITY.md) — Veltro agent security model
- [tools/godis/README.md](tools/godis/README.md) — Go-to-Dis compiler architecture
- [docs/WINDOWS-BUILD.md](docs/WINDOWS-BUILD.md) — Windows build and SDL3 GUI
- [docs/DIFFERENCES-FROM-STANDARD-INFERNO.md](docs/DIFFERENCES-FROM-STANDARD-INFERNO.md) — how InferNode differs from upstream
- [formal-verification/README.md](formal-verification/README.md) — TLA+, SPIN, CBMC proofs
- [docs/DOCUMENTATION-INDEX.md](docs/DOCUMENTATION-INDEX.md) — full index (100+ documents)

## Contributing

Contributions welcome — security audits, 9P integrations, bug fixes, and documentation all help. See [CONTRIBUTING.md](CONTRIBUTING.md).

## About

InferNode extends the MIT-licensed Inferno® OS with JIT compilers for AMD64 and ARM64, the Veltro AI agent system with formally verified namespace isolation, a cryptocurrency wallet with the x402 payment protocol, quantum-safe cryptography, a Go-to-Dis compiler, and an optional SDL3 GUI (Lucia + Xenith). It targets embedded systems, servers, and AI agent applications where a lightweight footprint and capability-based security matter.

## License

MIT, as with the original Inferno® OS. See [LICENSE](LICENSE).

---

<sub>Inferno® is a distributed operating system, originally developed at Bell Labs, and now maintained by trademark owner Vita Nuova®.</sub>
