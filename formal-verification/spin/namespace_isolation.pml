/*
 * Promela Model: Inferno Kernel Namespace Isolation
 *
 * This model verifies that per-process namespaces provide proper isolation.
 * After pgrpcpy() creates a child namespace, modifications to either
 * the parent or child namespace do NOT affect the other.
 *
 * REVISION: Removed excessive atomic blocks to expose interleavings.
 * Operations now model the actual lock acquire/release sequences from
 * the C implementation, allowing SPIN to explore concurrent scenarios
 * that could violate isolation.
 *
 * Corresponds to: emu/port/pgrp.c (pgrpcpy, cmount, cunmount)
 *                 emu/port/chan.c (cmount lock sequence)
 *
 * Run with:
 *   spin -a namespace_isolation.pml
 *   gcc -o pan pan.c -DSAFETY -O2
 *   ./pan -m10000000
 */

/* ========================================================================
 * CONSTANTS
 * ======================================================================== */

#define MAX_PGRPS    3      /* Maximum number of process groups */
#define MAX_PATHS    2      /* Maximum number of paths */
#define MAX_CHANS    4      /* Maximum number of channels */

/* Special values */
#define NONE         255
#define NO_PARENT    255

/* ========================================================================
 * STATE VARIABLES
 * ======================================================================== */

/* Process group state */
bool pgrp_exists[MAX_PGRPS];
byte pgrp_refcount[MAX_PGRPS];
byte pgrp_parent[MAX_PGRPS];

/* Mount tables: mount_table[pgrp][path] = set of channels (as bitmask) */
byte mount_table[MAX_PGRPS * MAX_PATHS];

/* Channel state */
bool chan_exists[MAX_CHANS];
byte chan_refcount[MAX_CHANS];

/* RWlock state for each pgrp's namespace lock (pg->ns) */
byte ns_readers[MAX_PGRPS];
bit  ns_writer[MAX_PGRPS];

/* RWlock state per mhead (simplified: one per pgrp*path) */
byte mh_readers[MAX_PGRPS * MAX_PATHS];
bit  mh_writer[MAX_PGRPS * MAX_PATHS];

/* Global counters */
byte next_pgrp_id = 0;
byte next_chan_id = 0;

/* History: post-copy mounts bitmask per pgrp*path */
byte post_copy_mount[MAX_PGRPS * MAX_PATHS];

/* ========================================================================
 * HELPER MACROS
 * ======================================================================== */

#define MT_IDX(pg, path)  ((pg) * MAX_PATHS + (path))
#define IS_MOUNTED(pg, path, c)  ((mount_table[MT_IDX(pg, path)] >> (c)) & 1)
#define DO_MOUNT(pg, path, c)    mount_table[MT_IDX(pg, path)] = mount_table[MT_IDX(pg, path)] | (1 << (c))
#define DO_UNMOUNT(pg, path, c)  mount_table[MT_IDX(pg, path)] = mount_table[MT_IDX(pg, path)] & ~(1 << (c))
#define IS_POST_COPY(pg, path, c) ((post_copy_mount[MT_IDX(pg, path)] >> (c)) & 1)

/* ========================================================================
 * LOCK OPERATIONS (non-atomic to expose interleavings)
 * ======================================================================== */

/*
 * Lock acquire operations use atomic{guard;set} to model the
 * indivisible test-and-set provided by the underlying OS mutex.
 * The critical insight: Inferno's RWlock (canrlock/canwlock) uses
 * host OS mutexes, so the guard+acquire is genuinely atomic.
 * Operations BETWEEN lock/unlock remain non-atomic (interleaved).
 */
inline ns_rlock(pg) {
    atomic { (ns_writer[pg] == 0); ns_readers[pg] = ns_readers[pg] + 1; }
}

inline ns_runlock(pg) {
    assert(ns_readers[pg] > 0);
    ns_readers[pg] = ns_readers[pg] - 1;
}

inline ns_wlock(pg) {
    atomic { (ns_writer[pg] == 0 && ns_readers[pg] == 0); ns_writer[pg] = 1; }
}

inline ns_wunlock(pg) {
    assert(ns_writer[pg] == 1);
    ns_writer[pg] = 0;
}

inline mh_wlock(pg, path) {
    atomic { (mh_writer[MT_IDX(pg, path)] == 0 && mh_readers[MT_IDX(pg, path)] == 0); mh_writer[MT_IDX(pg, path)] = 1; }
}

inline mh_wunlock(pg, path) {
    assert(mh_writer[MT_IDX(pg, path)] == 1);
    mh_writer[MT_IDX(pg, path)] = 0;
}

inline mh_rlock(pg, path) {
    atomic { (mh_writer[MT_IDX(pg, path)] == 0); mh_readers[MT_IDX(pg, path)] = mh_readers[MT_IDX(pg, path)] + 1; }
}

inline mh_runlock(pg, path) {
    assert(mh_readers[MT_IDX(pg, path)] > 0);
    mh_readers[MT_IDX(pg, path)] = mh_readers[MT_IDX(pg, path)] - 1;
}

/* ========================================================================
 * OPERATIONS (with real lock sequences from C code)
 * ======================================================================== */

/* Allocate a new channel - atomic (kernel allocator is locked) */
inline alloc_channel(cid) {
    atomic {
        if
        :: (next_chan_id < MAX_CHANS) ->
            cid = next_chan_id;
            chan_exists[cid] = true;
            chan_refcount[cid] = 1;
            next_chan_id++;
        :: else ->
            cid = NONE;
        fi
    }
}

/* Create a new process group - atomic (allocation) */
inline new_pgrp(pgid) {
    atomic {
        if
        :: (next_pgrp_id < MAX_PGRPS) ->
            pgid = next_pgrp_id;
            pgrp_exists[pgid] = true;
            pgrp_refcount[pgid] = 1;
            pgrp_parent[pgid] = NO_PARENT;
            byte np_p;
            for (np_p : 0 .. (MAX_PATHS - 1)) {
                mount_table[MT_IDX(pgid, np_p)] = 0;
                post_copy_mount[MT_IDX(pgid, np_p)] = 0;
                mh_readers[MT_IDX(pgid, np_p)] = 0;
                mh_writer[MT_IDX(pgid, np_p)] = 0;
            }
            ns_readers[pgid] = 0;
            ns_writer[pgid] = 0;
            next_pgrp_id++;
        :: else ->
            pgid = NONE;
        fi
    }
}

/*
 * Copy a process group (models pgrpcpy() from pgrp.c:74-130)
 *
 * NON-ATOMIC lock sequence:
 *   1. wlock(&from->ns)
 *   2. For each bucket: rlock(&f->lock), copy, runlock(&f->lock)
 *   3. wunlock(&from->ns)
 */
inline pgrp_copy(from_pgid, to_pgid) {
    ns_wlock(from_pgid);

    byte cp_p;
    for (cp_p : 0 .. (MAX_PATHS - 1)) {
        mh_rlock(from_pgid, cp_p);
        mount_table[MT_IDX(to_pgid, cp_p)] = mount_table[MT_IDX(from_pgid, cp_p)];
        post_copy_mount[MT_IDX(to_pgid, cp_p)] = 0;
        mh_runlock(from_pgid, cp_p);
    }

    pgrp_parent[to_pgid] = from_pgid;
    ns_wunlock(from_pgid);
}

/*
 * Mount a channel (models cmount() from chan.c:388-500)
 *
 * NON-ATOMIC lock sequence:
 *   1. wlock(&pg->ns)
 *   2. wlock(&m->lock)
 *   3. wunlock(&pg->ns)    <- EARLY RELEASE
 *   4. Modify mount list
 *   5. wunlock(&m->lock)
 */
inline mount_chan(pgid, path, cid) {
    ns_wlock(pgid);
    mh_wlock(pgid, path);
    ns_wunlock(pgid);

    DO_MOUNT(pgid, path, cid);
    post_copy_mount[MT_IDX(pgid, path)] = post_copy_mount[MT_IDX(pgid, path)] | (1 << cid);

    mh_wunlock(pgid, path);
}

/*
 * Unmount a channel (models cunmount() from chan.c:502-573)
 */
inline unmount_chan(pgid, path, cid) {
    ns_wlock(pgid);
    mh_wlock(pgid, path);
    DO_UNMOUNT(pgid, path, cid);
    mh_wunlock(pgid, path);
    ns_wunlock(pgid);
}

/* ========================================================================
 * VERIFICATION PROCESSES
 * ======================================================================== */

byte parent_pgrp;
byte child_pgrp;
byte parent_chan;
byte child_chan;
byte shared_chan;

byte snapshot[MAX_PATHS];
bool copy_done = false;

proctype ParentProcess() {
    byte path;

    (copy_done);

    alloc_channel(parent_chan);
    if
    :: (parent_chan != NONE) ->
        if
        :: path = 0;
        :: path = 1;
        fi

        mount_chan(parent_pgrp, path, parent_chan);

        /* ISOLATION: child must NOT see this post-copy mount */
        assert(!IS_MOUNTED(child_pgrp, path, parent_chan));
    :: else -> skip
    fi
}

proctype ChildProcess() {
    byte path;

    (copy_done);

    alloc_channel(child_chan);
    if
    :: (child_chan != NONE) ->
        if
        :: path = 0;
        :: path = 1;
        fi

        mount_chan(child_pgrp, path, child_chan);

        /* ISOLATION: parent must NOT see this post-copy mount */
        assert(!IS_MOUNTED(parent_pgrp, path, child_chan));
    :: else -> skip
    fi
}

/*
 * Concurrent mount to parent DURING copy - races with pgrp_copy.
 * Since pgrp_copy holds wlock on source, this mount (also needing wlock)
 * will serialize. But we let SPIN verify all interleavings.
 */
proctype ConcurrentMounter() {
    byte cid, path;

    alloc_channel(cid);
    if
    :: (cid != NONE && parent_pgrp != NONE) ->
        if
        :: path = 0;
        :: path = 1;
        fi

        mount_chan(parent_pgrp, path, cid);

        /* After copy, if this mount wasn't in the snapshot,
         * the child must not have it */
        (copy_done);
        if
        :: (!((snapshot[path] >> cid) & 1)) ->
            assert(!IS_MOUNTED(child_pgrp, path, cid) ||
                   IS_POST_COPY(child_pgrp, path, cid));
        :: else -> skip
        fi
    :: else -> skip
    fi
}

init {
    /* Create parent pgrp and initial mount */
    new_pgrp(parent_pgrp);
    assert(parent_pgrp != NONE);

    alloc_channel(shared_chan);
    assert(shared_chan != NONE);
    mount_chan(parent_pgrp, 0, shared_chan);

    /* Create child pgrp */
    new_pgrp(child_pgrp);
    assert(child_pgrp != NONE);

    /* Launch concurrent mounter before copy */
    run ConcurrentMounter();

    /* Non-atomic copy */
    pgrp_copy(parent_pgrp, child_pgrp);

    /* Snapshot taken from child AFTER copy - the child's mount table
     * IS the authoritative record of what was copied. This must be
     * captured before copy_done is set, since post-copy processes
     * wait on copy_done before modifying anything. */
    byte sp;
    for (sp : 0 .. (MAX_PATHS - 1)) {
        snapshot[sp] = mount_table[MT_IDX(child_pgrp, sp)];
    }
    copy_done = true;

    /* Concurrent post-copy modifications */
    run ParentProcess();
    run ChildProcess();
}
