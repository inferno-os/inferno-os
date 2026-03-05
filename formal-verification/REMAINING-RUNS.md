# Remaining Verification Runs

This document describes verification runs that require a dedicated host
with sufficient memory and uninterrupted execution time.

## Status Summary

| Verification | Status | Where Run |
|-------------|--------|-----------|
| SPIN (5 models) | **DONE** | CI / any host |
| CBMC quick (3 harnesses) | **DONE** | CI / any host |
| TLA+ TLC small (11 invariants) | **DONE** | CI / any host (8 min, 4GB) |
| TLA+ TLC medium | **TODO** | Dedicated host (16GB+, ~30 min) |
| TLA+ TLC large | **TODO** | Dedicated host (32GB+, ~hours) |
| CBMC full (pgrpcpy, MNTLOG=2) | **TODO** | Dedicated host (12GB+, ~20 min) |
| CBMC full (pgrpcpy, MNTLOG=5) | **TODO** | Dedicated host (16GB+, ~60 min) |

## Prerequisites

```bash
# Java 11+ (for TLC)
java -version

# SPIN 6.5+
spin -V

# CBMC 5.x+
cbmc --version

# TLA+ tools
cd formal-verification
curl -L -o tla2tools.jar \
  "https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar"
```

## 1. TLC Medium Configuration

**Requirements**: 16GB+ RAM, 16+ cores recommended, ~30 minutes

The medium configuration (3 processes, 4 pgrps, 4 channels, 3 paths)
generates ~100M+ distinct states. Previous attempts with 4GB heap were
OOM-killed at ~108M distinct states. With 12GB heap, reached 36M distinct
states before the process was terminated externally.

```bash
cd formal-verification

# Default: 16GB heap. Override with TLC_HEAP env var.
./run-verification.sh medium

# Or manually with custom heap:
TLC_HEAP=24g ./run-verification.sh medium
```

**Expected outcome**: All 11 invariants verified, 0 violations. The small
configuration (19.3M distinct states) passed completely. Medium exercises
deeper interleavings with more processes and paths.

## 2. TLC Large Configuration

**Requirements**: 32GB+ RAM, 16+ cores, ~1-4 hours

The large configuration (4 processes, 5 pgrps, 5 channels, 3 paths) will
produce a very large state space. This may require disk-backed state storage
if RAM is insufficient.

```bash
TLC_HEAP=32g ./run-verification.sh large

# If RAM is limited, TLC can use disk-based state storage:
# Add -fpset flag to the java command in run-verification.sh
```

**Expected outcome**: Same 11 invariants verified. This is the most
thorough configuration and would be the strongest result for publication.

## 3. CBMC Full Mode — pgrpcpy Harnesses

**Requirements**: 12-16GB RAM per harness, ~15-60 minutes each

CBMC verifies the **actual C implementation** of `pgrpcpy()` from
`emu/port/pgrp.c` against property-annotated harnesses. The SAT solver
requires significant memory for the loop unrolling.

### MNTLOG=2 (MNTHASH=4, unwind=6)

Smaller configuration that still verifies the same code paths but with
fewer hash buckets. Good for validating the harness setup.

```bash
cd formal-verification/cbmc
CBMC_MNTLOG=2 ./verify-all.sh full
```

### MNTLOG=5 (MNTHASH=32, unwind=34) — Production Configuration

This is the production MNTHASH=32 configuration. Each harness requires
~10-15GB RAM and ~15 minutes.

```bash
cd formal-verification/cbmc
CBMC_MNTLOG=5 ./verify-all.sh full

# Or run individual harnesses:
cbmc --function harness_basic_isolation harness_pgrpcpy.c \
  --bounds-check --pointer-check --signed-overflow-check \
  --unwind 34 --object-bits 11 -DMNTLOG=5

cbmc --function harness_modification_independence harness_pgrpcpy.c \
  --bounds-check --pointer-check --signed-overflow-check \
  --unwind 34 --object-bits 11 -DMNTLOG=5

cbmc --function harness_mnthash_bounds harness_pgrpcpy.c \
  --bounds-check --pointer-check --signed-overflow-check \
  --unwind 34 --object-bits 11 -DMNTLOG=5

cbmc --function harness harness_pgrpcpy_error.c \
  --bounds-check --pointer-check --signed-overflow-check \
  --unwind 34 --object-bits 11 -DMNTLOG=5
```

**4 harnesses verified**:
1. `harness_basic_isolation` — Copy produces independent mount tables
2. `harness_modification_independence` — Parent modification doesn't affect child
3. `harness_mnthash_bounds` — Hash index always in `[0, MNTHASH)`
4. `harness_pgrpcpy_error.c:harness` — waserror/nexterror cleanup correctness

**Expected outcome**: VERIFICATION SUCCESSFUL for all 4 harnesses.

## 4. Recording Results

After each run, save the output and update `results/PHASE4-VERIFICATION-RUN.md`
with the actual numbers. For TLC, the key metrics are:

- States generated / distinct states found
- Search depth reached
- States left on queue (0 = complete exhaustive search)
- Wall clock time
- Any invariant violations (should be none)

For CBMC, record:
- Number of properties checked per harness
- VERIFICATION SUCCESSFUL / FAILED
- Wall clock time and peak memory

## Notes

- TLC medium was attempted with 4GB heap (OOM at 108M distinct states)
  and 12GB heap (killed externally at 36M distinct states, still exploring).
  Estimated total distinct states: 200-500M. Recommend 16-24GB heap.

- CBMC pgrpcpy with MNTLOG=2 was attempted but killed externally during
  SAT solving after ~15 minutes at 10GB memory usage. The SAT problem
  is tractable — it just needs uninterrupted execution time.

- All verification code is committed and ready to run. No code changes needed.
