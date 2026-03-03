# Documentation Index

**Purpose:** Navigate InferNode documentation

## For Users

| Document | Description |
|----------|-------------|
| [USER-MANUAL.md](USER-MANUAL.md) | **Comprehensive user guide** - namespaces, devices, host integration |
| [QUICKSTART.md](../QUICKSTART.md) | Get running in 3 commands |
| [XENITH.md](XENITH.md) | Xenith AI-native text environment |
| [NAMESPACE.md](NAMESPACE.md) | Namespace architecture and configuration |
| [FILESYSTEM-MOUNTING.md](FILESYSTEM-MOUNTING.md) | Filesystem mounting guide |
| [DIFFERENCES-FROM-STANDARD-INFERNO.md](DIFFERENCES-FROM-STANDARD-INFERNO.md) | How InferNode differs from standard Inferno |

## For Developers

| Document | Description |
|----------|-------------|
| [CLAUDE.md](../CLAUDE.md) | Development guide for Claude Code (build, test, project structure) |
| [PERFORMANCE-SPECS.md](PERFORMANCE-SPECS.md) | Performance specifications and benchmarks |
| [BENCHMARKS.md](BENCHMARKS.md) | Benchmark results |
| [SDL3-GUI-PLAN.md](SDL3-GUI-PLAN.md) | SDL3 cross-platform GUI implementation plan |
| [SDL3-IMPLEMENTATION-STATUS.md](SDL3-IMPLEMENTATION-STATUS.md) | SDL3 implementation status |
| [RECOMMENDED-ADDITIONS.md](RECOMMENDED-ADDITIONS.md) | Recommended feature additions |

## Security

| Document | Description |
|----------|-------------|
| [SECURITY.md](../appl/veltro/SECURITY.md) | Veltro agent namespace security model |
| [NAMESPACE_SECURITY_REVIEW.md](NAMESPACE_SECURITY_REVIEW.md) | Namespace security analysis |
| [VELTRO_NAMESPACE_SECURITY.md](VELTRO_NAMESPACE_SECURITY.md) | Veltro namespace security details |

## Cryptography

| Document | Description |
|----------|-------------|
| [CRYPTO-MODERNIZATION.md](CRYPTO-MODERNIZATION.md) | Ed25519 signatures, SHA-256, key sizes |
| [CRYPTO-DEBUGGING-GUIDE.md](CRYPTO-DEBUGGING-GUIDE.md) | Debugging cryptographic code |
| [ELGAMAL-PERFORMANCE.md](ELGAMAL-PERFORMANCE.md) | ElGamal optimization |

## Porting Guide

| Document | Description |
|----------|-------------|
| [WINDOWS-BUILD.md](WINDOWS-BUILD.md) | Building and running on Windows (prerequisites, SDL3 GUI, troubleshooting) |
| [LESSONS-LEARNED.md](LESSONS-LEARNED.md) | **Start here** - Critical fixes and pitfalls for porters |
| [PORTING-ARM64.md](PORTING-ARM64.md) | ARM64 technical implementation details |
| [COMPILATION-LOG.md](COMPILATION-LOG.md) | Build process walkthrough |
| [JETSON-PORT-PLAN.md](JETSON-PORT-PLAN.md) | NVIDIA Jetson porting plan |
| [JETSON-PORT-ESTIMATE.md](JETSON-PORT-ESTIMATE.md) | Jetson port effort estimate |

## ARM64 JIT Compiler

Detailed JIT documentation is in `docs/arm64-jit/`.

## Debugging Reference

| Document | Description |
|----------|-------------|
| [OUTPUT-ISSUE.md](OUTPUT-ISSUE.md) | Console output debugging |
| [SHELL-ISSUE.md](SHELL-ISSUE.md) | Shell execution investigation |
| [HEADLESS-STATUS.md](HEADLESS-STATUS.md) | Headless build details |
| [TEMPFILE-EXHAUSTION.md](TEMPFILE-EXHAUSTION.md) | Temp file slot exhaustion |
| [64-bit-alt-structure-fix.md](64-bit-alt-structure-fix.md) | 64-bit alt structure fix |

## Formal Verification

See [formal-verification/README.md](../formal-verification/README.md) for TLA+, SPIN, and CBMC verification of namespace isolation.

## The Key 64-bit Fix

Pool quanta must be 127 for 64-bit (not 31 as for 32-bit). This single change in `emu/port/alloc.c` was the critical breakthrough that made the entire port work. See [LESSONS-LEARNED.md](LESSONS-LEARNED.md) for the full story.

## External References

- [inferno-os](https://github.com/inferno-os/inferno-os) - Upstream Inferno OS
- [inferno64](https://github.com/caerwynj/inferno64) - Reference 64-bit port
- [Inferno Shell paper](https://www.vitanuova.com/inferno/papers/sh.html)
- [EMU manual](https://vitanuova.com/inferno/man/1/emu.html)
