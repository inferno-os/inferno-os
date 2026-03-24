# Documentation Index

**Purpose:** Navigate InferNode documentation

## For Users

| Document | Description |
|----------|-------------|
| [USER-MANUAL.md](USER-MANUAL.md) | **Comprehensive user guide** - namespaces, devices, host integration |
| [QUICKSTART.md](../QUICKSTART.md) | Get running in 3 commands |
| [RUN_TOUR.md](../RUN_TOUR.md) | Interactive Veltro feature tour |
| [XENITH.md](XENITH.md) | Xenith AI-native text environment |
| [NAMESPACE.md](NAMESPACE.md) | Namespace architecture and configuration |
| [FILESYSTEM-MOUNTING.md](FILESYSTEM-MOUNTING.md) | Filesystem mounting guide |
| [DIFFERENCES-FROM-STANDARD-INFERNO.md](DIFFERENCES-FROM-STANDARD-INFERNO.md) | How InferNode differs from standard Inferno |

## Architecture & Design

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture, layer diagram, and component overview |
| [LUCIFER-EVALUATION.md](LUCIFER-EVALUATION.md) | Lucifer GUI production readiness evaluation (P0/P1/P2 issues) |
| [evaluations/fractal-app-evaluation.md](evaluations/fractal-app-evaluation.md) | Fractal app production readiness evaluation |
| [architecture-review-veltro-unification.md](architecture-review-veltro-unification.md) | Veltro architecture review |
| [RECOMMENDED-ADDITIONS.md](RECOMMENDED-ADDITIONS.md) | Recommended feature additions |

## For Developers

| Document | Description |
|----------|-------------|
| [CLAUDE.md](../CLAUDE.md) | Development guide for Claude Code (build, test, project structure) |
| [TESTING.md](TESTING.md) | Testing guide (unit tests, integration tests, CI) |
| [PERFORMANCE-SPECS.md](PERFORMANCE-SPECS.md) | Performance specifications and benchmarks |
| [BENCHMARKS.md](BENCHMARKS.md) | Benchmark results (v1, v2, v3 suites) |
| [SDL3-GUI-PLAN.md](SDL3-GUI-PLAN.md) | SDL3 cross-platform GUI implementation plan |
| [SDL3-IMPLEMENTATION-STATUS.md](SDL3-IMPLEMENTATION-STATUS.md) | SDL3 implementation status |

## Wallet & Payments

| Document | Description |
|----------|-------------|
| [WALLET-AND-PAYMENTS.md](WALLET-AND-PAYMENTS.md) | **Comprehensive guide** - wallet9p, x402 protocol, secstore, factotum, key persistence, login screen |

## Security

| Document | Description |
|----------|-------------|
| [SECURITY.md](../SECURITY.md) | Security vulnerability reporting policy |
| [SECURITY.md (Veltro)](../appl/veltro/SECURITY.md) | Veltro agent namespace security model (v3) |
| [NAMESPACE_SECURITY_REVIEW.md](NAMESPACE_SECURITY_REVIEW.md) | Namespace security deep analysis |
| [VELTRO_NAMESPACE_SECURITY.md](VELTRO_NAMESPACE_SECURITY.md) | Veltro namespace security details |

## Cryptography

| Document | Description |
|----------|-------------|
| [CRYPTO-MODERNIZATION.md](CRYPTO-MODERNIZATION.md) | Ed25519 signatures, SHA-256, key sizes |
| [QUANTUM-SAFE-CRYPTO-PLAN.md](QUANTUM-SAFE-CRYPTO-PLAN.md) | ML-KEM, ML-DSA, SLH-DSA (FIPS 203/204/205) |
| [CRYPTO-DEBUGGING-GUIDE.md](CRYPTO-DEBUGGING-GUIDE.md) | Debugging cryptographic code |
| [ELGAMAL-PERFORMANCE.md](ELGAMAL-PERFORMANCE.md) | ElGamal optimization |
| [TLS-ENTROPY.md](TLS-ENTROPY.md) | TLS entropy configuration |

## Porting Guide

| Document | Description |
|----------|-------------|
| [WINDOWS-BUILD.md](WINDOWS-BUILD.md) | Building and running on Windows (prerequisites, SDL3 GUI, troubleshooting) |
| [LESSONS-LEARNED.md](LESSONS-LEARNED.md) | **Start here** - Critical fixes and pitfalls for porters |
| [PORTING-ARM64.md](PORTING-ARM64.md) | ARM64 technical implementation details |
| [COMPILATION-LOG.md](COMPILATION-LOG.md) | Build process walkthrough |
| [JETSON-PORT-PLAN.md](JETSON-PORT-PLAN.md) | NVIDIA Jetson porting plan |
| [JETSON-PORT-ESTIMATE.md](JETSON-PORT-ESTIMATE.md) | Jetson port effort estimate |
| [COMPLETE-PORT-SUMMARY.md](COMPLETE-PORT-SUMMARY.md) | Port completion summary |

## ARM64 JIT Compiler

Detailed JIT documentation is in `docs/arm64-jit/` (27 files covering implementation, debugging, benchmarks across all platforms).

## Additional Guides

| Document | Description |
|----------|-------------|
| [PDF.md](PDF.md) | PDF support documentation |
| [SPEECH-REMOTE-AUDIO.md](SPEECH-REMOTE-AUDIO.md) | Speech and remote audio |
| [RUNNING-ACME.md](RUNNING-ACME.md) | Running the Acme editor |
| [SONARQUBE_WORK.md](SONARQUBE_WORK.md) | SonarQube static analysis work |

## Debugging Reference

| Document | Description |
|----------|-------------|
| [OUTPUT-ISSUE.md](OUTPUT-ISSUE.md) | Console output debugging |
| [SHELL-ISSUE.md](SHELL-ISSUE.md) | Shell execution investigation |
| [HEADLESS-STATUS.md](HEADLESS-STATUS.md) | Headless build details |
| [TEMPFILE-EXHAUSTION.md](TEMPFILE-EXHAUSTION.md) | Temp file slot exhaustion |
| [64-bit-alt-structure-fix.md](64-bit-alt-structure-fix.md) | 64-bit alt structure fix |
| [FONT-RENDERING-DEBUG.md](FONT-RENDERING-DEBUG.md) | Font rendering debugging |

## Formal Verification

See [formal-verification/README.md](../formal-verification/README.md) for TLA+, SPIN, and CBMC verification of namespace isolation (3 tools, 11 properties, 3.17B+ states explored).

## GoDis Compiler

See [tools/godis/README.md](../tools/godis/README.md) for the Go-to-Dis compiler architecture, translation strategy, and 190+ passing tests.

## The Key 64-bit Fix

Pool quanta must be 127 for 64-bit (not 31 as for 32-bit). This single change in `emu/port/alloc.c` was the critical breakthrough that made the entire port work. See [LESSONS-LEARNED.md](LESSONS-LEARNED.md) for the full story.

## External References

- [inferno-os](https://github.com/inferno-os/inferno-os) - Upstream Inferno OS
- [inferno64](https://github.com/caerwynj/inferno64) - Reference 64-bit port
- [Inferno Shell paper](https://www.vitanuova.com/inferno/papers/sh.html)
- [EMU manual](https://vitanuova.com/inferno/man/1/emu.html)
