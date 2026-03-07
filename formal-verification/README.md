# Inferno Kernel Formal Verification

This directory contains formal specifications and verification scripts for the Inferno kernel's namespace isolation mechanism.

## Overview

The Inferno kernel provides **per-process namespaces** that isolate each process's view of the file system. This formal verification effort proves that:

1. **Namespace Isolation**: After `pgrpcpy()` copies a namespace, modifications to the child namespace do NOT affect the parent, and vice versa.
2. **Reference Counting Correctness**: Reference counts are always non-negative and objects are properly freed.
3. **No Use-After-Free**: Freed resources are not accessed.
4. **Locking Protocol Safety**: Deadlock freedom and correct lock ordering.
5. **Race Condition Analysis**: Identifies potential data races in `Sys_pctl`, `kchdir`, and `namec`.
6. **Export Boundary Safety**: `exportfs` root boundary cannot be bypassed.
7. **Implementation Fidelity**: CBMC verifies actual C code, not models.

## Verification Status

| Phase | Tool | Focus | Status |
|-------|------|-------|--------|
| 1 | TLA+ | Abstract namespace isolation (non-trivial invariants) | **Verified** (small: exhaustive; medium: 3.17B states, 0 violations) |
| 1 | SPIN | Namespace isolation with non-atomic operations | **Verified** (5/5 models pass) |
| 2 | SPIN | Multi-lock locking protocol (per-pgrp, per-mhead) | **Verified** |
| 3 | CBMC | Real C code verification (pgrpcpy, closepgrp) | **Verified** (quick: 3/3 pass; full pgrpcpy: pending) |
| 4 | SPIN | Race conditions (pctl/kchdir/namec) | **Verified** (3 real races found) |
| 5 | SPIN | exportfs root boundary | **Verified** |
| CI | GH Actions | Automated verification on push | **Active** |

See [results/](results/) for detailed verification reports.

## Files

```
formal-verification/
├── README.md                                  # This file
├── PLAN-namespace-security-verification.md    # Gap analysis and work plan
├── run-verification.sh                        # TLC model checker script
├── tla+/
│   ├── Namespace.tla                         # Core spec (history vars, namec, kchdir)
│   ├── NamespaceProperties.tla               # Non-trivial isolation invariants
│   ├── IsolationProof.tla                    # Isolation theorem (non-tautological)
│   ├── MC_Namespace.tla                      # Model checking configuration
│   └── MC_Namespace.cfg                      # TLC configuration (medium defaults)
├── spin/
│   ├── namespace_isolation.pml               # Non-atomic isolation model
│   ├── namespace_isolation_extended.pml      # Extended model (nested fork)
│   ├── namespace_locks.pml                   # Multi-lock protocol model
│   ├── namespace_races.pml                   # Race conditions (pctl/kchdir/namec)
│   ├── exportfs_boundary.pml                 # Export root escape verification
│   ├── verify-locks.sh                       # Legacy locking verification
│   └── verify-all.sh                         # Run all SPIN models
├── cbmc/
│   ├── stubs.h                               # CBMC stubs for kernel types
│   ├── harness_pgrpcpy.c                     # pgrpcpy isolation (real code)
│   ├── harness_pgrpcpy_error.c               # pgrpcpy error path safety
│   ├── harness_mnthash_bounds.c              # Array bounds harness
│   ├── harness_overflow_simple.c             # Integer overflow harness
│   ├── harness_refcount.c                    # Reference counting harness
│   └── verify-all.sh                         # CBMC verification script
└── results/
    ├── VERIFICATION-RESULTS.md               # Phase 1 results
    ├── PHASE2-LOCKING-RESULTS.md             # Phase 2 results
    └── PHASE3-CBMC-RESULTS.md                # Phase 3 results
```

## Quick Start

### Run All SPIN Verification

```bash
# Install SPIN
apt-get install -y spin   # Linux
brew install spin         # macOS

# Quick verification (for CI)
cd formal-verification/spin
./verify-all.sh quick

# Full verification with LTL properties
./verify-all.sh full
```

### Run All CBMC Verification

```bash
# Install CBMC
apt-get install -y cbmc   # Linux
brew install cbmc         # macOS

cd formal-verification/cbmc
./verify-all.sh
```

### Run TLA+ Verification

```bash
# Requires Java 11+ and tla2tools.jar
cd formal-verification
./run-verification.sh small    # ~minutes
./run-verification.sh medium   # ~hours
./run-verification.sh large    # ~days
```

## Key Properties Verified

### Namespace Isolation (Non-Trivial)

The core isolation property uses **history variables** to track post-copy mutations:

```
NamespaceIsolation ==
  ∀ pg_child ∈ PgrpId :
    let pg_parent = pgrp_parent[pg_child] in
    (active(pg_child) ∧ active(pg_parent)) ⟹
      ∀ path, cid :
        (⟨path, cid⟩ ∈ post_copy_mounts[pg_parent] ∧
         cid ∈ mount_table[pg_parent][path]) ⟹
          (cid ∈ mount_table[pg_child][path] ⟹
            ⟨path, cid⟩ ∈ post_copy_mounts[pg_child])
```

This says: if a channel was mounted in the parent AFTER the copy, it does NOT appear in the child's mount table UNLESS the child independently mounted it. This is NOT tautologically true — it depends on the correctness of `Mount`, `PgrpCopy`, and the separation of mount table data structures.

### Additional Properties

| Property | Description | Tool |
|----------|-------------|------|
| `NamespaceIsolation` | Post-copy mounts don't leak across namespaces | TLA+/SPIN |
| `UnilateralMountNonPropagation` | Unilateral mount never appears in other namespace | TLA+ |
| `CopyFidelity` | Copy produces exact duplicate of source | TLA+/CBMC |
| `PostCopyMountsSound` | History tracking is accurate | TLA+ |
| `MountLocalityProperty` | Each step modifies at most one pgrp | TLA+ |
| `RefCountNonNegative` | Refcounts ≥ 0 | TLA+/CBMC |
| `NoUseAfterFree` | Freed objects not accessed | TLA+/SPIN |
| `DeadlockFreedom` | No deadlocks in concurrent ns operations | SPIN |
| `LockOrdering` | pg->ns always acquired before m->lock | SPIN |
| `ArrayBounds` | MOUNTH macro always produces valid index | CBMC |
| `IntegerOverflow` | fd allocation arithmetic is safe | CBMC |
| `ExportBoundary` | walk("..") cannot escape export root | SPIN |

## Correspondence to C Code

| Operation | C Function | Source File | Verified By |
|-----------|------------|-------------|-------------|
| `NewPgrp` | `newpgrp()` | `emu/port/pgrp.c:8` | TLA+ |
| `PgrpCopy` / `ForkWithForkNS` | `pgrpcpy()` | `emu/port/pgrp.c:74` | TLA+, SPIN, CBMC |
| `ClosePgrp` | `closepgrp()` | `emu/port/pgrp.c:23` | TLA+, SPIN |
| `Mount` | `cmount()` | `emu/port/chan.c:388` | TLA+, SPIN |
| `Unmount` | `cunmount()` | `emu/port/chan.c:502` | TLA+, SPIN |
| `NameResolve` | `namec()` | `emu/port/chan.c:997` | TLA+, SPIN (race) |
| `ChangeDir` | `kchdir()` | `emu/port/sysfile.c:142` | TLA+, SPIN (race) |
| `ForkWithNewNS` | `Sys_pctl(NEWNS)` | `emu/port/inferno.c:855` | TLA+, SPIN (race) |
| `ForkWithForkNS` | `Sys_pctl(FORKNS)` | `emu/port/inferno.c:869` | TLA+, SPIN (race) |
| `findmount` | `findmount()` | `emu/port/chan.c:592` | SPIN |
| `walk` | `walk()` | `emu/port/chan.c:685` | SPIN (export) |

## Trusted Computing Base (TCB)

The verification trusts:
1. Hardware executes correctly
2. C compiler is correct (gcc)
3. Host OS provides correct threading primitives
4. Memory allocator returns valid memory or nil
5. SPIN, CBMC, and TLC tools are correct
6. The stubs in `cbmc/stubs.h` faithfully model kernel primitives

## Known Limitations

1. **Bounded verification**: TLA+/TLC and CBMC explore finite state spaces. For unbounded proofs, interactive theorem proving (Isabelle/HOL) would be needed.
2. **Abstraction gap**: SPIN models abstract lock semantics; the real RWlock implementation is not verified at the assembly level.
3. **Race condition findings**: The `namespace_races.pml` model may report races that are benign under Inferno's cooperative threading model (one Dis thread at a time), but are real at the C/emu level with multiple host threads.
4. **`nodevs` exception consistency**: Verified via manual audit — both `namec()` and `devindir.c` use identical exception string `"|esDa"`.

## CI/CD Integration

Formal verification runs automatically on push/PR via `.github/workflows/formal-verification.yml`:
- SPIN: Quick mode (safety checks) on every push
- CBMC: All harnesses on every push

## References

1. Klein et al., "seL4: Formal Verification of an OS Kernel", SOSP 2009
2. Nelson et al., "Hyperkernel: Push-Button Verification of an OS Kernel", SOSP 2017
3. Ferraiuolo et al., "Komodo: Using Verification to Disentangle Secure-Enclave Hardware from Software", SOSP 2017
4. Lamport, "Specifying Systems: The TLA+ Language and Tools for Hardware and Software Engineers"
5. Holzmann, "The SPIN Model Checker: Primer and Reference Manual"
6. Clarke et al., "Bounded Model Checking Using Satisfiability Solving"

---

*Last updated: 2026-03-07*
