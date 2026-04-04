# Contributing to InferNode

Thank you for your interest in InferNode. This is a modernized fork of
Inferno® OS with 64-bit support, JIT compilation, AI agents, and post-quantum
cryptography. Contributions of all kinds are welcome — from typo fixes to new
9P integrations to security audits.

## Where to Start

If you're new to the project:

1. Read the [Quick Start Guide](QUICKSTART.md) to build and run InferNode
2. Browse [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a system overview
3. Try the [Interactive Tour](RUN_TOUR.md) to explore features hands-on
4. Look at issues labeled **good first issue** for approachable tasks

## What InferNode Needs

### Security Testing & Auditing *(high priority)*

InferNode runs a virtual machine, implements post-quantum cryptography, and
exposes a 9P network filesystem. Security is critical. We especially need:

- **Fuzz testing** of the Dis VM interpreter and JIT compilers (`libinterp/`)
- **9P protocol boundary testing** — the export filesystem
  (`emu/port/exportfs.c`) and mount driver (`emu/port/devmnt.c`) are
  network-facing attack surfaces
- **Cryptographic review** of our FIPS 203/204/205 implementations (ML-KEM,
  ML-DSA, SLH-DSA) in `libsec/`
- **Namespace escape analysis** — try to break out of the capability sandbox.
  See `formal-verification/` for existing proofs (3.17 billion states checked
  via TLA+, plus SPIN and CBMC verification)
- **Race condition analysis** — SPIN model checking found 3 real races in
  kernel code; more analysis and severity assessment is welcome
- **Static analysis improvements** — we run CodeQL, cppcheck, and flawfinder
  in CI; help us expand coverage or triage findings

If you find a vulnerability, please report it privately per our
[Security Policy](SECURITY.md). We coordinate fixes before public disclosure.

### 9P Tool Integrations

InferNode's architecture lets you connect *anything* as a filesystem using the
9P protocol. This is conceptually similar to the MCP server ecosystem, but
instead of JSON-RPC, everything is files — reading and writing files controls
tools, queries data, and connects systems.

The Veltro agent system already has **39 tool modules** exposed via `tools9p`.
Each tool is a Limbo module that serves a synthetic filesystem under `/tool/`.
An AI agent (or any program) interacts with external services by reading and
writing files — no new protocol to learn.

**Integrations we'd love to see:**

| Category | Examples |
|----------|---------|
| Communication | Matrix, Discord, IRC, XMPP, Slack |
| Productivity | CalDAV/CardDAV, Jira, Linear, Notion, Todoist |
| Data stores | PostgreSQL, Redis, SQLite, S3-compatible storage |
| Infrastructure | Docker, Kubernetes, cloud provider APIs |
| Monitoring | Prometheus, Grafana, system metrics |
| IoT / sensors | Hardware sensors, GPIO, MQTT |

**How to write one:** Look at `appl/veltro/tools9p.b` for how tools are served,
and individual tool modules in `appl/veltro/tools/` (e.g., `http.b`,
`git.b`, `mail.b`) for the pattern. Each tool has a corresponding documentation
file in `lib/veltro/tools/`. The `styxservers` library (`appl/lib/styxservers.b`)
provides high-level helpers for implementing 9P fileservers.

### Windows Experience

Windows support works (headless + SDL3 GUI) but needs polish:

- **Installer/packaging** — MSI, MSIX, or `winget` package instead of manual
  build from source
- **JIT compiler** — the AMD64 JIT works on Linux but hasn't been ported to
  Windows (different calling conventions, memory protection APIs). This would
  give Windows users a ~14x performance boost.
- **SDL3 GUI testing** — Xenith and Lucia run on Windows via SDL3/D3D12 but
  need more real-world testing
- **Developer experience** — better error messages, path handling, and docs for
  developers without Unix experience

See [docs/WINDOWS-BUILD.md](docs/WINDOWS-BUILD.md) and
`build-windows-amd64.ps1`.

### GoDis Compiler

The Go-to-Dis compiler (`tools/godis/`) compiles Go source to Dis bytecode.
It's preliminary — 190+ tests passing — and a great area for compiler
enthusiasts:

- Expanding Go language feature coverage
- Improving Dis bytecode generation
- Adding optimization passes
- Test coverage for edge cases

### Platform Testing

We ship on Linux (x86-64, ARM64), macOS (ARM64), and Windows (x86-64).
Testing and fixes on other platforms would be valuable:

- **FreeBSD, OpenBSD, NetBSD** — emulator code exists but is lightly tested
- **ARM64 single-board computers** — Raspberry Pi, NVIDIA Jetson, Pine64
- **Linux ARM64 GUI** — the SDL3/Vulkan backend is ~95% complete
- **RISC-V** — no support yet; the Dis VM is portable and this would be a
  significant contribution

### Formal Verification

We have TLA+, SPIN, and CBMC proofs of critical security properties. Areas to
expand:

- Extended CBMC harnesses for `pgrpcpy` and reference counting
- Severity and reproducibility analysis of the 3 races found by SPIN
- New properties: memory safety bounds, channel protocol verification

See `formal-verification/README.md` and `formal-verification/METHODOLOGY.md`.

### Documentation

- Limbo language tutorials (it's like a cross between C and Go — few resources
  exist outside the Inferno community)
- 9P protocol guides with practical examples
- Architecture deep-dives on specific subsystems
- Troubleshooting guides (build issues, common runtime errors)

## Development Setup

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| macOS ARM64 | Xcode Command Line Tools |
| Linux x86-64 | GCC, make |
| Linux ARM64 | GCC, make |
| Windows x86-64 | Visual Studio 2022 Build Tools |

### Building

```bash
# Clone
git clone https://github.com/NERVsystems/infernode.git
cd infernode

# Install the post-merge hook (prevents stale bytecode after pulls)
./hooks/install.sh

# Linux x86-64
./build-linux-amd64.sh

# Linux ARM64
./build-linux-arm64.sh

# macOS ARM64 (pre-built toolchain ships in repo)
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH
cd appl/cmd; mk install

# Windows (from x64 Native Tools Command Prompt)
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1
```

### Running the Emulator

```bash
# Linux
./emu/Linux/o.emu -r.

# macOS
./emu/MacOSX/o.emu -r.
```

```powershell
# Windows
.\emu\Nt\o.emu.exe -r .
```

### Running Tests

Tests run inside the Inferno emulator:

```bash
# Build tests (macOS example; use Linux paths on Linux)
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH
cd tests; mk install; cd ..

# Run all tests
./emu/MacOSX/o.emu -r. /tests/runner.dis -v

# Run a specific test
./emu/MacOSX/o.emu -r. /tests/crypto_test.dis
```

See [CLAUDE.md](CLAUDE.md) for the full testing API reference and build details.

## Making a Contribution

### Workflow

1. **Fork** the repository on GitHub
2. **Clone** your fork and run `./hooks/install.sh`
3. **Create a branch** from `master` for your work
4. **Make your changes** and run the test suite
5. **Commit** with clear, descriptive messages
6. **Push** to your fork and open a **pull request**

### Build System Notes

InferNode uses Plan 9's `mk` (not GNU make). Important points:

- Use InferNode's **native build tools** (`mk`, `limbo`), not Plan 9 Port
- Build from your host OS terminal, not inside the Inferno emulator
- `mkfile` in each directory defines build rules
- `mk install` compiles and copies output to `dis/`
- `mk nuke` cleans build artifacts
- Don't use `&&` to chain commands in mkfiles — use `;` or separate rules

### Code Style

- **Limbo** (`.b` files): Follow the style of surrounding code. Tabs for
  indentation. Opening braces on the same line as the control structure.
- **C** (`libinterp/`, `emu/`, `lib*/`): K&R style, tabs for indentation.
  Match the existing Plan 9/Inferno conventions.
- **Shell scripts**: POSIX `/bin/sh` compatible. No bash-isms.

### Commit Messages

Write clear messages that explain *why*, not just *what*. Keep the first line
under 72 characters.

```
crypto: add test vectors for ML-KEM decapsulation

The existing tests only covered encapsulation. Add NIST ACVP test
vectors for decapsulation to verify round-trip correctness.
```

### What Not to Commit

- `.dis` files in `appl/` or `tests/` — build artifacts, `.gitignore`d
- `.dis` files in `dis/` — the runtime tree is tracked, but changes should
  only result from `mk install` in the corresponding `appl/` directory
- Secrets, API keys, or credentials of any kind

### Pull Request Guidelines

- **Keep PRs focused** — one logical change per PR
- **Include tests** when changing behavior
- **Update docs** when changing interfaces or adding features
- **Run the test suite** before submitting
- **Describe the motivation** — what problem does this solve?

CI will automatically run:
- Build verification (Linux x86-64, macOS ARM64)
- CodeQL semantic analysis
- cppcheck and flawfinder static analysis
- Formal verification (if kernel or namespace code changed)
- OSSF Scorecard (supply chain security)

## Understanding the Codebase

### Key Directories

| Directory | Language | What's There |
|-----------|----------|-------------|
| `libinterp/` | C | Dis VM interpreter and JIT compilers |
| `emu/port/` | C | Kernel: namespaces, 9P, devices, memory |
| `libsec/` | C | Cryptography: AES-GCM, ChaCha20, ML-KEM, Ed25519 |
| `appl/veltro/` | Limbo | AI agent system, 9P tool servers |
| `appl/xenith/` | Limbo | Text environment (Acme-inspired, AI-native) |
| `appl/cmd/` | Limbo | Standard utilities (ls, cat, mount, etc.) |
| `appl/lib/` | Limbo | Libraries (styx, styxservers, JSON, TLS, etc.) |
| `module/` | Limbo | Interface definitions (like header files) |
| `formal-verification/` | TLA+/SPIN/CBMC | Security proofs |
| `tools/godis/` | Go | Go-to-Dis compiler |

### The Limbo Language

Limbo is InferNode's application language. If you know C and Go, you'll pick
it up quickly:

- C-like syntax with `:=` type-inferring declarations
- First-class channels and `spawn` (like Go's goroutines and channels)
- Module system with explicit `load` — no implicit linking
- Garbage collected, type-safe, compiles to portable Dis bytecode
- `alt` statement for selecting across multiple channels

The best way to learn is to read `appl/cmd/` for simple utilities and
`module/sys.m` for the system call interface.

### The Inferno Shell

InferNode's shell (`sh`) is rc-style, **not** POSIX:

- No `&&` operator — use `;` or separate commands
- `for` loops: `for i in $list { commands }`
- Different quoting rules than bash/zsh

This matters when writing scripts that run inside the emulator.

## Community

- **Issues**: [GitHub Issues](https://github.com/NERVsystems/infernode/issues)
  for bugs, feature requests, and questions
- **Security**: Report vulnerabilities privately via our
  [Security Policy](SECURITY.md) — do **not** open public issues
- **Code of Conduct**: Please read our
  [Code of Conduct](CODE_OF_CONDUCT.md) before participating

## License

By contributing, you agree that your contributions will be licensed under the
same terms as the project. InferNode uses a dual-license scheme — see
[LICENCE](LICENCE) for details. The kernel and libraries are under permissive
terms (Lucent Public License / MIT-style); the VM library and applications are
LGPL/GPL.

---

Every contribution matters — whether it's a security audit, a new 9P tool
integration, a Windows installer, a Limbo tutorial, or a one-line bug fix.
Thank you for helping build InferNode.
