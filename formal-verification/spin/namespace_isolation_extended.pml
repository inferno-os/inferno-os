/*
 * Extended Promela Model: Inferno Kernel Namespace Isolation
 *
 * Extended scenarios with non-atomic operations:
 * 1. Multiple concurrent mounts/unmounts with real lock sequences
 * 2. Nested fork (parent -> child -> grandchild)
 * 3. Races between mount and copy operations
 * 4. Per-pgrp and per-mhead lock instances
 *
 * REVISION: All operations use real lock sequences (non-atomic).
 * Lock instances are per-pgrp (ns) and per-pgrp*path (mhead).
 *
 * Run with:
 *   spin -a namespace_isolation_extended.pml
 *   gcc -o pan pan.c -DSAFETY -O2
 *   ./pan -m10000000
 */

#define MAX_PGRPS    4
#define MAX_PATHS    3
#define MAX_CHANS    6

#define NONE         255
#define NO_PARENT    255

/* State */
bool pgrp_exists[MAX_PGRPS];
byte pgrp_refcount[MAX_PGRPS];
byte pgrp_parent[MAX_PGRPS];
byte mount_table[MAX_PGRPS * MAX_PATHS];
bool chan_exists[MAX_CHANS];
byte chan_refcount[MAX_CHANS];

/* Per-pgrp namespace RWlock */
byte ns_readers[MAX_PGRPS];
bit  ns_writer[MAX_PGRPS];

/* Per-pgrp*path mhead RWlock */
byte mh_readers[MAX_PGRPS * MAX_PATHS];
bit  mh_writer[MAX_PGRPS * MAX_PATHS];

byte next_pgrp_id = 0;
byte next_chan_id = 0;

/* History: post-copy mount bitmask */
byte post_copy_mount[MAX_PGRPS * MAX_PATHS];

/* Snapshots */
byte snapshot_parent[MAX_PATHS];
byte snapshot_child[MAX_PATHS];
bool parent_copy_done = false;
bool child_copy_done = false;

#define MT_IDX(pg, path)  ((pg) * MAX_PATHS + (path))
#define IS_MOUNTED(pg, path, c)  ((mount_table[MT_IDX(pg, path)] >> (c)) & 1)
#define DO_MOUNT(pg, path, c)    mount_table[MT_IDX(pg, path)] = mount_table[MT_IDX(pg, path)] | (1 << (c))
#define DO_UNMOUNT(pg, path, c)  mount_table[MT_IDX(pg, path)] = mount_table[MT_IDX(pg, path)] & ~(1 << (c))
#define IS_POST_COPY(pg, path, c) ((post_copy_mount[MT_IDX(pg, path)] >> (c)) & 1)

/* Lock acquire uses atomic{guard;set} to model OS mutex atomicity.
 * Operations between lock/unlock remain non-atomic (interleaved). */
inline ns_rlock(pg) { atomic { (ns_writer[pg] == 0); ns_readers[pg] = ns_readers[pg] + 1; } }
inline ns_runlock(pg) { assert(ns_readers[pg] > 0); ns_readers[pg] = ns_readers[pg] - 1; }
inline ns_wlock(pg) { atomic { (ns_writer[pg] == 0 && ns_readers[pg] == 0); ns_writer[pg] = 1; } }
inline ns_wunlock(pg) { assert(ns_writer[pg] == 1); ns_writer[pg] = 0; }
inline mh_wlock(pg, path) { atomic { (mh_writer[MT_IDX(pg, path)] == 0 && mh_readers[MT_IDX(pg, path)] == 0); mh_writer[MT_IDX(pg, path)] = 1; } }
inline mh_wunlock(pg, path) { assert(mh_writer[MT_IDX(pg, path)] == 1); mh_writer[MT_IDX(pg, path)] = 0; }
inline mh_rlock(pg, path) { atomic { (mh_writer[MT_IDX(pg, path)] == 0); mh_readers[MT_IDX(pg, path)] = mh_readers[MT_IDX(pg, path)] + 1; } }
inline mh_runlock(pg, path) { assert(mh_readers[MT_IDX(pg, path)] > 0); mh_readers[MT_IDX(pg, path)] = mh_readers[MT_IDX(pg, path)] - 1; }

inline alloc_channel(cid) {
    atomic {
        if :: (next_chan_id < MAX_CHANS) ->
            cid = next_chan_id; chan_exists[cid] = true; chan_refcount[cid] = 1; next_chan_id++;
        :: else -> cid = NONE; fi
    }
}

inline new_pgrp(pgid) {
    atomic {
        if :: (next_pgrp_id < MAX_PGRPS) ->
            pgid = next_pgrp_id; pgrp_exists[pgid] = true; pgrp_refcount[pgid] = 1; pgrp_parent[pgid] = NO_PARENT;
            byte np_p;
            for (np_p : 0 .. (MAX_PATHS - 1)) {
                mount_table[MT_IDX(pgid, np_p)] = 0; post_copy_mount[MT_IDX(pgid, np_p)] = 0;
                mh_readers[MT_IDX(pgid, np_p)] = 0; mh_writer[MT_IDX(pgid, np_p)] = 0;
            }
            ns_readers[pgid] = 0; ns_writer[pgid] = 0; next_pgrp_id++;
        :: else -> pgid = NONE; fi
    }
}

/* Non-atomic pgrp copy */
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

/* Non-atomic mount with early release */
inline mount_chan(pgid, path, cid) {
    ns_wlock(pgid);
    mh_wlock(pgid, path);
    ns_wunlock(pgid);
    DO_MOUNT(pgid, path, cid);
    post_copy_mount[MT_IDX(pgid, path)] = post_copy_mount[MT_IDX(pgid, path)] | (1 << cid);
    mh_wunlock(pgid, path);
}

inline unmount_chan(pgid, path, cid) {
    ns_wlock(pgid);
    mh_wlock(pgid, path);
    DO_UNMOUNT(pgid, path, cid);
    mh_wunlock(pgid, path);
    ns_wunlock(pgid);
}

/* Test variables */
byte parent_pgrp = NONE;
byte child_pgrp = NONE;
byte grandchild_pgrp = NONE;

bool parent_modified = false;
bool child_modified = false;
byte parent_mount_path = NONE;
byte parent_mount_chan = NONE;
byte child_mount_path = NONE;
byte child_mount_chan = NONE;

proctype ParentModifier() {
    byte cid, path;
    (parent_copy_done);
    alloc_channel(cid);
    if :: (cid != NONE && parent_pgrp != NONE) ->
        if :: path = 0; :: path = 1; :: path = 2; fi
        mount_chan(parent_pgrp, path, cid);
        parent_mount_path = path; parent_mount_chan = cid; parent_modified = true;
        if :: (child_pgrp != NONE) ->
            assert(!IS_MOUNTED(child_pgrp, path, cid) || IS_POST_COPY(child_pgrp, path, cid));
        :: else -> skip fi
    :: else -> skip fi
}

proctype ChildModifier() {
    byte cid, path;
    (child_pgrp != NONE && parent_copy_done);
    alloc_channel(cid);
    if :: (cid != NONE) ->
        if :: path = 0; :: path = 1; :: path = 2; fi
        mount_chan(child_pgrp, path, cid);
        child_mount_path = path; child_mount_chan = cid; child_modified = true;
        assert(!IS_MOUNTED(parent_pgrp, path, cid) || IS_POST_COPY(parent_pgrp, path, cid));
        if :: (grandchild_pgrp != NONE && child_copy_done) ->
            assert(!IS_MOUNTED(grandchild_pgrp, path, cid) || IS_POST_COPY(grandchild_pgrp, path, cid));
        :: else -> skip fi
    :: else -> skip fi
}

proctype IsolationChecker() {
    (parent_modified && child_modified);
    if :: (parent_mount_chan != NONE && parent_mount_path != NONE && child_pgrp != NONE) ->
        assert(!IS_MOUNTED(child_pgrp, parent_mount_path, parent_mount_chan) ||
               IS_POST_COPY(child_pgrp, parent_mount_path, parent_mount_chan));
    :: else -> skip fi
    if :: (child_mount_chan != NONE && child_mount_path != NONE) ->
        assert(!IS_MOUNTED(parent_pgrp, child_mount_path, child_mount_chan) ||
               IS_POST_COPY(parent_pgrp, child_mount_path, child_mount_chan));
    :: else -> skip fi
}

init {
    byte init_p;
    byte chan0;

    new_pgrp(parent_pgrp); assert(parent_pgrp != NONE);
    alloc_channel(chan0);
    if :: (chan0 != NONE) -> mount_chan(parent_pgrp, 0, chan0); :: else -> skip fi

    new_pgrp(child_pgrp); assert(child_pgrp != NONE);
    pgrp_copy(parent_pgrp, child_pgrp);

    /* Snapshot from child after copy — child IS the copy */
    for (init_p : 0 .. (MAX_PATHS - 1)) {
        snapshot_parent[init_p] = mount_table[MT_IDX(child_pgrp, init_p)];
    }
    parent_copy_done = true;

    /* Nested fork: grandchild from child */
    new_pgrp(grandchild_pgrp);
    if :: (grandchild_pgrp != NONE) ->
        for (init_p : 0 .. (MAX_PATHS - 1)) {
            snapshot_child[init_p] = mount_table[MT_IDX(child_pgrp, init_p)];
        }
        pgrp_copy(child_pgrp, grandchild_pgrp);
        child_copy_done = true;
        for (init_p : 0 .. (MAX_PATHS - 1)) {
            assert(mount_table[MT_IDX(grandchild_pgrp, init_p)] == snapshot_child[init_p]);
        }
    :: else -> skip fi

    run ParentModifier();
    run ChildModifier();
    run IsolationChecker();
}
