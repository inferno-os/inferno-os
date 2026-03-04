# Phase 4: Verification Run Results

*Date: 2026-03-04*

## SPIN Model Checking Results

All 5 SPIN models pass verification in quick mode.

### Summary

| Model | File | Status | States Explored |
|-------|------|--------|----------------|
| Basic Isolation | `namespace_isolation.pml` | **PASS** | 82,628 |
| Extended Isolation (nested fork) | `namespace_isolation_extended.pml` | **PASS** | 5,724 |
| Multi-Lock Protocol | `namespace_locks.pml` | **PASS** | 39,744 |
| Namespace Races | `namespace_races.pml` | **PASS** | 3,131 |
| exportfs Root Boundary | `exportfs_boundary.pml` | **PASS** | 106 |
| **Total** | | **5/5 PASS** | **131,333** |

### Bugs Fixed During Run

1. **Lock Atomicity (all models)**: Lock acquire operations (guard + flag set) were non-atomic, allowing two processes to pass the same guard before either set the flag. Fixed by wrapping guard+assignment in `atomic{}` blocks, correctly modeling the OS mutex that backs Inferno's RWlock.

2. **Snapshot Timing (namespace_isolation.pml)**: The parent mount table snapshot was captured before the copy, but a `ConcurrentMounter` could serialize its mount before `pgrp_copy` (both need `ns_wlock`). The child then legitimately received the mount via copy, but the stale snapshot caused a false assertion failure. Fixed by taking the snapshot from the child's mount table after the copy completes.

3. **Lock Ordering Verification (namespace_locks.pml)**: LTL formula with struct array indexing too complex for SPIN's parser. Replaced with structural inline assertions: assert ns is held before each mhead lock acquire.

4. **Promela Reserved Word (namespace_races.pml)**: Variable named `chan` conflicted with Promela's channel keyword. Renamed to `ch`.

### Race Conditions Found (Expected)

The `namespace_races.pml` model successfully detects real race conditions in the kernel C code:

- **kchdir dot race**: `kchdir()` does `cclose(pg->dot); pg->dot = c;` without a lock. Between `cclose` and assignment, concurrent `namec()` can read the freed channel via `pg->dot`. **Use-after-free confirmed by LTL violation.**

- **FORKNS pgrp swap race**: `Sys_pctl(FORKNS)` swaps `o->pgrp` without lock. A cached pgrp pointer in another thread becomes stale.

- **namec slash/dot read race**: `namec()` reads `pg->slash`/`pg->dot` without holding `pg->ns`. Concurrent `kchdir` or `FORKNS` could invalidate these pointers.

These are real bugs at the C/emu thread level. They are mitigated by Inferno's cooperative Dis VM scheduling (only one Dis thread at a time), but are genuine hazards for the multi-threaded emu host layer.

## CBMC Bounded Model Checking Results

### Quick Mode (CI)

| Harness | File | Status | Properties Checked |
|---------|------|--------|-------------------|
| Array Bounds (mnthash) | `harness_mnthash_bounds.c` | **PASS** | 58 |
| Integer Overflow (fd) | `harness_overflow_simple.c` | **PASS** | 10 |
| Reference Counting | `harness_refcount.c` | **PASS** | 45 |
| **Total** | | **3/3 PASS** | **113** |

### Full Mode (Manual)

The `harness_pgrpcpy.c` harness (basic isolation, modification independence, mnthash bounds) verifies actual C code from `pgrp.c` with MNTHASH=32 loop unrolling. This requires:
- ~15 minutes per sub-harness
- ~10GB RAM per sub-harness
- `--unwind 34 --object-bits 11`

Run with: `CBMC_MNTLOG=5 ./verify-all.sh full`

## Key Findings

1. **Namespace isolation is verified at two levels**:
   - **SPIN** explores 131,333 states confirming post-copy mount isolation in Promela models.
   - **TLA+/TLC** exhaustively checks 369,414,154 states (19.3M distinct) verifying 11 safety invariants including the NamespaceIsolationTheorem, UnilateralMountNonPropagation, CopyFidelity, and PostCopyMountsSound.

2. **Lock ordering is verified**: All 39,744 states of the locking protocol model confirm that `pg->ns` is always acquired before `m->lock`, with correct handling of cmount's early-release optimization.

3. **Export boundary is verified**: The `exportfs` root boundary cannot be escaped via `walk("..")` sequences, including mount point confusion scenarios.

4. **Three real race conditions documented**: The race model provides formal evidence for three use-after-free hazards in the emu host threading layer. See `TODO-RACE-CONDITIONS.md` for details and suggested fixes.

5. **CBMC confirms implementation properties**: Array bounds (MOUNTH macro), integer overflow (fd allocation), and reference counting are verified on actual C code paths.

## TLA+ / TLC Model Checking Results

### Small Configuration (exhaustive)

| Parameter | Value |
|-----------|-------|
| MaxProcesses | 2 |
| MaxPgrps | 3 |
| MaxChannels | 3 |
| MaxPaths | 2 |
| MaxMountId | 4 |

| Metric | Value |
|--------|-------|
| States generated | 369,414,154 |
| Distinct states | 19,307,332 |
| Search depth | 27 |
| States left on queue | 0 (complete) |
| Time | 7 min 57 sec |
| Workers | 16 |
| Memory | 4 GB heap |

### Invariants Verified

All 11 safety invariants verified with no violations:

| Invariant | Module | Description |
|-----------|--------|-------------|
| TypeOK | Namespace | Type safety of all state variables |
| SafetyInvariant | NamespaceProperties | Combined safety (types + refcounts + no-UAF + bounds) |
| RefCountNonNegative | NamespaceProperties | Reference counts never go negative |
| NoUseAfterFree | NamespaceProperties | Freed pgrps not assigned to processes |
| MountTableBounded | NamespaceProperties | Mount tables contain valid channel IDs |
| NamespaceIsolation | NamespaceProperties | Post-copy mounts don't leak across namespaces |
| NamespaceIsolationTheorem | IsolationProof | If channel in both parent+child, either from snapshot or independently mounted |
| UnilateralMountNonPropagation | IsolationProof | Unilateral mount in one namespace never appears in the other |
| CopyFidelity | NamespaceProperties | Fresh copy's mount table equals snapshot |
| PostCopyMountsSound | IsolationProof | Every mount is from snapshot or tracked as post-copy |
| NoIsolationViolation | IsolationProof | Negation of isolation violation predicate |

### TLA+ Model Bug Fixed During Run

**IncRefChannel unbounded refcount**: `IncRefChannel` could increment channel refcounts beyond `RefCountVal`, violating `TypeOK`. Added bound guard (`chan_refcount[cid] < MaxProcesses + MaxPgrps + MaxChannels`). This is a model-checking artifact — real refcounts are naturally bounded by the finite number of references in the system.

### Operations Modeled

The TLA+ spec covers 12 operations: `CreateProcess`, `ForkWithForkNS`, `ForkWithNewNS`, `ForkWithSharedNS`, `TerminateProcess`, `SetNoDevs`, `AllocChannel`, `IncRefChannel`, `DecRefChannel`, `Mount`, `Unmount`, `ChangeDir`. History variables (`copy_snapshot`, `pgrp_parent`, `post_copy_mounts`) enable non-trivial isolation verification.
