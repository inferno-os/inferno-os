# TODO: Race Conditions Found by Formal Verification

*Identified: 2026-03-04 via SPIN model checking (`namespace_races.pml`)*

These are **real bugs** at the C/emu host threading level. They are mitigated
by Inferno's cooperative Dis VM scheduling (only one Dis thread at a time), but
are genuine hazards for the multi-threaded emu host layer where multiple emu
threads (for I/O, timers, etc.) can access the Osenv concurrently.

---

## BUG 1: kchdir dot use-after-free

**File:** `emu/port/sysfile.c:142-157`
**Severity:** High (use-after-free)
**Confirmed by:** SPIN LTL violation (`no_use_after_free_dot`)

### Description

`kchdir()` performs:
```c
cclose(pg->dot);    // STEP A: free old dot channel
pg->dot = c;        // STEP B: assign new dot channel
```
No lock is held between steps A and B. Between `cclose` and the assignment,
a concurrent `namec()` call can read `pg->dot` and get the freed channel pointer.

### Suggested Fix

Hold `pg->ns` write lock (or a dedicated dot/slash lock) around the
close-and-reassign sequence:
```c
wlock(&pg->ns);
cclose(pg->dot);
pg->dot = c;
wunlock(&pg->ns);
```

---

## BUG 2: Sys_pctl FORKNS pgrp pointer swap

**File:** `emu/port/inferno.c:869-876`
**Severity:** Medium (stale pointer)
**Confirmed by:** SPIN model (`sys_pctl_forkns` proctype)

### Description

`Sys_pctl` with `FORKNS` flag performs:
```c
release();                  // Let other emu threads run
np = newpgrp();
pgrpcpy(np, o->pgrp);
opg = o->pgrp;
o->pgrp = np;              // SWAP — no lock!
closepgrp(opg);
acquire();
```
After `release()`, other emu threads can run. If another thread has cached
`up->env->pgrp`, the pointer becomes stale after the swap. If `closepgrp(opg)`
frees the old pgrp (refcount drops to 0), the cached pointer is dangling.

### Suggested Fix

Use an atomic compare-and-swap or hold a lock around the pgrp pointer swap.
Alternatively, ensure `closepgrp` is deferred until all readers have released
their references (reference counting on the pgrp pointer itself).

---

## BUG 3: namec reading slash/dot without lock

**File:** `emu/port/chan.c:1020-1058`
**Severity:** Medium (stale read)
**Confirmed by:** SPIN LTL violation (`no_use_after_free_slash`)

### Description

`namec()` reads `pg->slash` or `pg->dot` without holding `pg->ns`:
```c
case '/':
    c = up->env->pgrp->slash;   // NO LOCK
    incref(&c->r);
    break;
default:
    c = up->env->pgrp->dot;     // NO LOCK
    incref(&c->r);
    break;
```
Concurrent `kchdir` (BUG 1) or `Sys_pctl FORKNS` (BUG 2) could free or
replace these pointers between the read and the `incref`.

### Suggested Fix

Either:
1. Hold `pg->ns` read lock around the slash/dot read + incref, or
2. Use atomic pointer operations (load-linked/store-conditional or equivalent)
   to ensure the channel pointer is valid before incrementing its refcount.

---

## Notes

- All three races share a root cause: pointer reads/writes to shared `Pgrp`
  fields without synchronization at the emu host thread level.
- In practice, Inferno's cooperative Dis scheduling means only one Dis thread
  accesses these at a time. The races affect emu I/O threads and timer threads.
- A comprehensive fix would add read-lock protection to `pg->dot` and
  `pg->slash` accesses in `namec()` and write-lock protection in `kchdir()`.
- The SPIN model (`formal-verification/spin/namespace_races.pml`) provides
  reproducible counterexamples for all three races.
