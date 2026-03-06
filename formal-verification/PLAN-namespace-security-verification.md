# Plan: Namespace Security Verification — Closing Gaps for Publication

## Goal
Bring the Infernode namespace isolation formal verification to an academically
publishable standard, suitable for venues like USENIX Security, OSDI, or FM/CAV.

## Current State Assessment

### What Exists
- TLA+ spec (Namespace.tla, NamespaceProperties.tla, IsolationProof.tla)
- SPIN models: namespace isolation (basic + extended), locking protocol
- CBMC harnesses: mnthash bounds, integer overflow, reference counting
- Results claiming all properties verified

### Critical Problems Found

**P1 — Tautological TLA+ Properties (SEVERITY: BLOCKER)**
`NamespaceIsolation` and `NoRetroactiveContamination` in NamespaceProperties.tla
both reduce to `=> TRUE`. The model uses TLA+ functions where `mount_table[pg1]`
is inherently distinct from `mount_table[pg2]` when `pg1 ≠ pg2`. The "proof" proves
nothing about the C implementation — isolation is true by construction of the model,
not by any deep property of the operations. A reviewer would reject immediately.

**P2 — Trivial State Spaces (SEVERITY: HIGH)**
SPIN explores 83–4,830 states. Academic SPIN papers routinely explore 10⁶–10⁹.
The models use `atomic` blocks for all operations, hiding the very interleavings
where bugs occur. TLC was never actually run (no TLC output in results).

**P3 — CBMC Harnesses Don't Verify Real Code (SEVERITY: HIGH)**
The refcount harness creates its own `incref_checked`/`decref_checked` rather than
pointing CBMC at the actual `incref()`/`decref()` in the source. Other harnesses
similarly re-implement simplified logic. This verifies models, not code.

**P4 — Major Functions Unverified (SEVERITY: HIGH)**
The namespace attack surface is much larger than what's verified:
- `namec()` (chan.c:997) — every file operation goes through it; reads `slash`/`dot`
  without locks
- `walk()` (chan.c:685) — core path-walking through mount points
- `Sys_pctl()` (inferno.c:789) — NEWNS/FORKNS swaps `o->pgrp` without locks
- `kchdir()` (sysfile.c:142) — writes `pg->dot` without any lock
- `findmount()` (chan.c:592) — defensive nil check suggests suspected race
- `exportfs` root escape — walk-above-root check via `eqchan()` only compares
  `qid.path`

**P5 — Missing Error Path Modeling (SEVERITY: MEDIUM)**
`pgrpcpy()` uses `waserror()`/`nexterror()` for exception handling. If malloc fails
mid-copy, the namespace is left partially copied. None of the models cover this.

**P6 — No CI/CD Integration (SEVERITY: MEDIUM)**
Verification is not reproducible in the pipeline.

**P7 — No Refinement Chain (SEVERITY: MEDIUM)**
There is no formal link between the TLA+ abstract model and the C implementation.
Academic work requires showing the implementation refines the specification.

---

## Implementation Plan

### Phase A: Fix TLA+ Specification (Write Real Properties)

**A1. Rewrite NamespaceIsolation as a non-trivial invariant**

Replace the tautological `=> TRUE` with a property that actually tracks state:

- Add a `snapshot` variable that records mount table state at copy time
- Add an `operations_since_copy` history variable tracking post-fork mounts
- Define isolation as: for any post-fork mount M applied to pg1, M does not
  appear in pg2's mount table (and vice versa)
- This requires the model to track *which* operations were applied to *which*
  pgrp, making the property testable

Files to modify:
- `formal-verification/tla+/Namespace.tla` — add history/snapshot variables
- `formal-verification/tla+/NamespaceProperties.tla` — rewrite NamespaceIsolation,
  NoRetroactiveContamination with real invariants
- `formal-verification/tla+/IsolationProof.tla` — rewrite with real lemmas

**A2. Increase TLC model checking constants and actually run TLC**

- Update `MC_Namespace.cfg` with medium defaults (3 processes, 4 pgrps, 4 chans,
  3 paths) — target 10⁵+ states
- Ensure `run-verification.sh` works end-to-end
- Record actual TLC output in results

**A3. Add `namec()`-level operations to TLA+ model**

The current model only has Mount/Unmount. Real namespace operations go through
`namec()`, which resolves paths via `slash`/`dot` channels. Add:
- `NameResolve(pgid, path)` operation that reads slash/dot then walks mount table
- `ChangeDir(pgid, path)` operation modeling kchdir writing pg->dot
- These are needed to verify that name resolution respects isolation

Files to modify:
- `formal-verification/tla+/Namespace.tla` — add NameResolve, ChangeDir operations
  and slash/dot state variables

### Phase B: Fix SPIN Models (Non-Atomic, Larger State Space)

**B1. Remove excessive `atomic` blocks from isolation models**

The current SPIN models wrap all operations in `atomic` — `pgrp_copy`,
`mount_chan`, etc. This hides the critical interleavings (what happens if a mount
races with a copy mid-operation?). Remove atomicity from:
- `pgrp_copy` — should model the loop over MNTHASH buckets non-atomically
- `mount_chan` — should model lock acquire, hash lookup, insertion as separate steps
- Keep `alloc_channel` atomic (allocation is effectively atomic in the kernel)

Files to modify:
- `formal-verification/spin/namespace_isolation.pml`
- `formal-verification/spin/namespace_isolation_extended.pml`

**B2. Add `namec`/path resolution to SPIN locking model**

`namec()` acquires `rlock(&pg->ns)` indirectly via `findmount()`/`domount()`.
But it reads `pg->slash` and `pg->dot` *without any lock*. Model this:
- Add a `namec` proctype that reads slash/dot, then calls findmount
- Add a `kchdir` proctype that writes dot without locks
- Add a `sys_pctl` proctype that swaps pgrp pointer without locks
- Verify no data race exists (or discover one)

Files to create:
- `formal-verification/spin/namespace_races.pml`

**B3. Model multiple lock instances in locking model**

Current model has a single `pg_ns` and single `mhead_lock`. Real system has one
`pg->ns` per pgrp and one `m->lock` per Mhead. With multiple lock instances:
- Two cmounts to different pgrps can proceed in parallel
- Two cmounts to the same pgrp but different mheads can overlap after early release
- This significantly increases the state space (target: 10⁶+ states)

Files to modify:
- `formal-verification/spin/namespace_locks.pml` — add arrays of locks

### Phase C: Fix CBMC Harnesses (Verify Actual C Code)

**C1. Create harnesses that `#include` actual source files**

Instead of re-implementing logic, create harnesses that include the real C source
with minimal stubs for dependencies:

- `harness_pgrpcpy.c` — includes `pgrp.c`, stubs `malloc`/`wlock`/`rlock`/etc.,
  drives `pgrpcpy()` with symbolic inputs, asserts isolation post-condition
- `harness_closepgrp.c` — drives real `closepgrp()`, verifies no double-free
- `harness_cmount.c` — drives real `cmount()`, verifies mount locality
- `harness_findmount.c` — drives real `findmount()`, verifies correct lookup

Create a comprehensive `stubs.h` with CBMC-compatible stubs for:
- Memory allocation (`malloc` returning symbolic non-null or null)
- Locking primitives (track lock state in ghost variables)
- Channel operations (`cclose`, `incref`, `decref`)
- Error handling (`waserror`/`poperror`/`nexterror`)

Files to create:
- `formal-verification/cbmc/stubs.h`
- `formal-verification/cbmc/harness_pgrpcpy.c`
- `formal-verification/cbmc/harness_closepgrp.c`
- `formal-verification/cbmc/harness_cmount.c`
- `formal-verification/cbmc/harness_findmount.c`

Files to modify:
- `formal-verification/cbmc/verify-all.sh` — add new harnesses

**C2. Add error path harnesses**

Verify partial-copy safety in pgrpcpy when malloc fails mid-copy:
- Set up a pgrp with mounts across multiple hash buckets
- Make malloc fail after N successful allocations (symbolic N)
- Verify the waserror cleanup path leaves the source pgrp intact
- Verify no dangling pointers in the destination pgrp

Files to create:
- `formal-verification/cbmc/harness_pgrpcpy_error.c`

### Phase D: Verify Ancillary Attack Surfaces

**D1. Model `Sys_pctl` NEWNS/FORKNS pgrp swap**

In `inferno.c:863-875`, the pgrp pointer is swapped:
```c
opg = o->pgrp;
o->pgrp = np.np;
```
This happens while `release()` has been called (line 809), meaning other kernel
threads may be running. If another thread reads `o->pgrp` between the old value
being read and the new being written, it could use a freed pgrp.

Create a SPIN model specifically for this race:
- Process A: executing Sys_pctl FORKNS sequence
- Process B: executing namec which reads o->pgrp->slash
- Check if B can see a stale/freed pgrp

Files to create:
- `formal-verification/spin/pctl_race.pml`

**D2. Model `kchdir` dot-writing race**

`kchdir()` (sysfile.c:142-157) does:
```c
pg = up->env->pgrp;
cclose(pg->dot);
pg->dot = c;
```
No lock is held. If concurrent `namec()` reads `pg->dot` between the cclose and
the assignment, it could use a freed channel.

Add this scenario to the races model from B2.

**D3. Verify `exportfs` root boundary**

The exportfs server walks paths within an exported subtree. If `walk("..")`
can escape above the exported root, namespace isolation is violated from the
network side. Create a CBMC harness or SPIN model that verifies the root
boundary check in exportfs cannot be bypassed.

Files to create:
- `formal-verification/spin/exportfs_boundary.pml` or
  `formal-verification/cbmc/harness_exportfs_root.c`

**D4. Verify `nodevs` exception consistency**

The `nodevs` flag restricts device access, but exceptions are hardcoded in
`namec()` (chan.c:1047-1048) as `"|esDa"`. If other code paths have different
exception lists, a bypass exists. Audit and verify consistency.

This is a static analysis / grep task — document the finding.

### Phase E: CI/CD Integration

**E1. Add SPIN verification to CI**

Add a job to `.github/workflows/ci.yml` that:
- Installs SPIN (`apt-get install -y spin`)
- Runs all three SPIN models
- Fails the build if any verification fails

**E2. Add CBMC verification to CI**

Add a job that:
- Installs CBMC
- Runs `verify-all.sh`
- Fails the build if any harness fails

**E3. Add TLA+ verification to CI (optional)**

TLC requires Java and can be slow. Consider running only the "small" config
in CI and document "medium"/"large" as manual pre-release checks.

Files to modify:
- `.github/workflows/ci.yml`

### Phase F: Documentation and Results Update

**F1. Update all results files**

After re-running with fixed models:
- `results/VERIFICATION-RESULTS.md` — new TLA+ and SPIN state counts
- `results/PHASE2-LOCKING-RESULTS.md` — updated with multi-lock model
- `results/PHASE3-CBMC-RESULTS.md` — updated with real-code harnesses
- New: `results/PHASE4-RACES-RESULTS.md` — race condition analysis
- New: `results/PHASE5-ANCILLARY-RESULTS.md` — exportfs, kchdir, pctl results

**F2. Write a verification summary suitable for paper appendix**

- Clear statement of TCB (what's trusted)
- Complete list of verified properties with formal statements
- Correspondence table: every namespace-touching function → which tool verified it
- Known limitations stated honestly
- State space statistics

**F3. Update README.md**

Reflect new verification scope and status.

---

## Execution Order

Phases can be partially parallelized:

```
A (TLA+ fix) ──────────────> F (docs)
B (SPIN fix) ──────────────> F
C (CBMC fix) ──────────────> F
D (ancillary) ─────────────> F
E (CI/CD) ─────────────────> F
```

Within each phase, items are sequential (A1 before A2 before A3, etc.).

**Recommended priority order**: A1 → B1 → C1 → D1 → A2 → B2 → C2 → D2 → A3 →
B3 → D3 → D4 → E1 → E2 → F1 → F2 → F3

This addresses the highest-severity issues first (tautological properties,
atomic blocks hiding races, harnesses not testing real code, pctl race condition).

---

## What This Achieves

After completing this plan:

1. **No tautological properties** — isolation invariants are real, testable, and
   can fail if the model is wrong
2. **Meaningful state spaces** — 10⁵+ TLC states, 10⁶+ SPIN states
3. **Real code verification** — CBMC harnesses include actual C source
4. **Complete attack surface** — namec, walk, pctl, kchdir, exportfs all covered
5. **Error path coverage** — malloc failure during pgrpcpy verified
6. **Race condition analysis** — the pgrp swap and dot-writing races are modeled
7. **Reproducible** — CI runs verification on every push
8. **Honestly documented** — TCB and limitations clearly stated

This brings the verification to a standard comparable to Hyperkernel (SOSP 2017)
for push-button verification, or the workshop/FM track for model-checking-based
approaches. Full seL4-level proofs would require Isabelle/HOL, which is out of
scope for this effort.
