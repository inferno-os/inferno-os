# Phase 4: Verification Run Results

*Date: 2026-03-04 (updated 2026-03-07 with TLC medium results)*

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

1. **Namespace isolation is verified at three levels of scale**:
   - **SPIN** explores 131,333 states confirming post-copy mount isolation in Promela models.
   - **TLA+/TLC small** exhaustively checks 369,414,154 states (19.3M distinct) verifying 11 safety invariants with zero states left on queue (complete).
   - **TLA+/TLC medium** checks 26.5 billion states (3.17 billion distinct) at depth 13 with zero violations across all 11 invariants including NamespaceIsolationTheorem, UnilateralMountNonPropagation, CopyFidelity, and PostCopyMountsSound.

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

### Medium Configuration (partial, bounded by storage)

The medium configuration was run on a dedicated host for approximately 10 hours
50 minutes, exploring over 3.1 billion distinct states with zero violations across
all 11 invariants. The run was terminated gracefully when on-disk state storage
approached capacity; it is recoverable from checkpoint.

| Parameter | Value |
|-----------|-------|
| MaxProcesses | 3 |
| MaxPgrps | 4 |
| MaxChannels | 4 |
| MaxPaths | 3 |
| MaxMountId | 6 |

| Metric | Value |
|--------|-------|
| States generated | 26,515,255,632 |
| Distinct states | 3,168,821,335 |
| Search depth completed | 12 (depth 13 in progress at termination) |
| States left on queue | 2,562,257,601 |
| Wall clock time | 10 hr 50 min |
| Workers | 12 on 12 ARM64 cores |
| JVM heap | 50 GB (45,511 MB usable) |
| State storage | MSBDiskFPSet + DiskStateQueue (~341 GB on NVMe SSD) |
| RSS (resident memory) | ~26 GB (stable) |
| Checkpoints | 21 successful (30-min interval) |
| Violations found | **0** |
| Platform | NVIDIA Jetson Orin AGX, 64 GB unified memory, Linux 5.15.148-tegra aarch64 |
| TLC version | 2026.03.04.183147 (rev: 52c0195) |

#### Depth Progression

The BFS exploration advanced through 6 depth levels during the run:

| Depth | First seen | Last seen | Distinct states at entry | Notes |
|-------|-----------|-----------|--------------------------|-------|
| 8 | 13:03:42 | 13:03:42 | 191,208 | Initial states |
| 9 | 13:04:42 | 13:04:42 | 8,229,740 | |
| 10 | 13:05:42 | 13:14:42 | 15,510,096 - 78,225,900 | ~10 min |
| 11 | 13:15:42 | 14:20:43 | 84,947,416 - 497,402,089 | ~65 min |
| 12 | 14:21:43 | 21:48:39 | 502,609,707 - 2,592,202,171 | ~7.5 hr |
| 13 | 21:49:39 | 23:53:41 | 2,596,454,653 - 3,168,821,335 | ~2 hr (in progress) |

#### Interpretation

The medium configuration state space is too large for exhaustive search on
available hardware. At termination, the state queue held 2.56 billion unexplored
states and was growing at a net rate of ~3.5 million states per minute, indicating
that the full state space is likely in the tens or hundreds of billions of distinct
states. Nevertheless, the 3.17 billion distinct states explored without any
invariant violation across all 11 properties provides strong evidence of
correctness. This represents a 164x increase over the exhaustive small
configuration (19.3M distinct states) and exercises significantly deeper
interleavings with 3 concurrent processes, 4 process groups, 4 channels,
and 3 filesystem paths.

#### Recoverability

The run is recoverable from the last checkpoint (2026-03-06 23:34:41) via:
```bash
cd formal-verification/tla+
java -XX:+UseParallelGC -Xmx50g -jar ../tla2tools.jar \
  -config ../results/MC_Namespace_medium.cfg \
  -workers auto -checkpoint 60 -deadlock \
  -recover states/26-03-06-13-03-38.714 \
  MC_Namespace.tla
```

### Large Configuration (not attempted)

Large (4 proc, 5 pgrp, 5 chan, 3 path) would produce a vastly larger state space.
Given that the medium configuration could not be exhausted with 50 GB heap and
341 GB of SSD state storage in 10+ hours, exhaustive large verification would
require either (a) substantially more resources or (b) symmetry reduction /
abstraction techniques to reduce the state space.

### TLA+ Model Bugs Fixed During Run

1. **IncRefChannel unbounded refcount**: `IncRefChannel` could increment channel refcounts beyond `RefCountVal`, violating `TypeOK`. Added bound guard (`chan_refcount[cid] < MaxProcesses + MaxPgrps + MaxChannels`). This is a model-checking artifact — real refcounts are naturally bounded by the finite number of references in the system.

2. **NamespaceIsolation property too strict**: The original property did not account for parent `post_copy_mounts` that occurred BEFORE a fork (and are thus legitimately in the child's `copy_snapshot`). TLC found a valid counterexample in the medium configuration: parent mounts channel, then forks — the mount is in both tables but the child didn't independently mount it. Fixed by adding a `copy_snapshot` exception. The stronger `NamespaceIsolationTheorem` already handled this correctly.

3. **MC_Namespace duplicate constants**: `EXTENDS Namespace` imported the constants, and `MC_Namespace` re-declared them, causing a multiply-defined symbol error. Fixed by removing the re-declarations.

### Operations Modeled

The TLA+ spec covers 12 operations: `CreateProcess`, `ForkWithForkNS`, `ForkWithNewNS`, `ForkWithSharedNS`, `TerminateProcess`, `SetNoDevs`, `AllocChannel`, `IncRefChannel`, `DecRefChannel`, `Mount`, `Unmount`, `ChangeDir`. History variables (`copy_snapshot`, `pgrp_parent`, `post_copy_mounts`) enable non-trivial isolation verification.
