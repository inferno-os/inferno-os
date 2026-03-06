/*
 * SPIN Model for Inferno Namespace Race Conditions
 *
 * Models race conditions in namespace operations that occur
 * WITHOUT proper locking in the actual C implementation:
 *
 * RACE 1: Sys_pctl FORKNS pgrp pointer swap (inferno.c:869-875)
 *   - Process A calls Sys_pctl(FORKNS), swaps o->pgrp without lock
 *   - Process B reads o->pgrp (via namec) concurrently
 *   - B could see stale/freed pgrp if A's closepgrp runs first
 *
 * RACE 2: kchdir dot-writing race (sysfile.c:142-157)
 *   - Process A calls kchdir, does: cclose(pg->dot); pg->dot = c;
 *   - Process B calls namec, reads pg->dot for path resolution
 *   - B could read freed channel between cclose and assignment
 *
 * RACE 3: namec reading slash/dot without lock (chan.c:1020-1058)
 *   - namec reads pg->slash or pg->dot without holding pg->ns
 *   - Concurrent FORKNS could change the pgrp pointer
 *
 * These model ACTUAL potential bugs in the kernel code.
 *
 * Run with:
 *   spin -a namespace_races.pml
 *   gcc -o pan pan.c -DSAFETY -O2
 *   ./pan -m10000000
 */

/* Channel states */
#define CHAN_FREED    0
#define CHAN_VALID    1
#define CHAN_CLOSING  2

/* Pgrp states */
#define PGRP_FREED   0
#define PGRP_VALID   1
#define PGRP_CLOSING 2

/* Number of pgrps and channels */
#define NUM_PGRPS    3
#define NUM_CHANS    4

/* State */
byte pgrp_state[NUM_PGRPS];    /* FREED, VALID, CLOSING */
byte pgrp_refcount[NUM_PGRPS];
byte pgrp_dot[NUM_PGRPS];      /* Channel ID used as dot */
byte pgrp_slash[NUM_PGRPS];    /* Channel ID used as slash */
byte chan_state[NUM_CHANS];     /* FREED, VALID, CLOSING */
byte chan_refcount[NUM_CHANS];

/* Process's current pgrp pointer (o->pgrp) */
byte process_pgrp[2];  /* 2 processes sharing an Osenv */

/* Verification flags */
bool use_after_free_dot = false;
bool use_after_free_pgrp = false;
bool use_after_free_slash = false;

/* ========== RACE 1: Sys_pctl FORKNS ========== */

/*
 * Models Sys_pctl with FORKNS flag (inferno.c:869-876):
 *
 *   release();                    // Let other threads run
 *   np.np = newpgrp();
 *   pgrpcpy(np.np, o->pgrp);
 *   opg = o->pgrp;               // Read old pgrp
 *   o->pgrp = np.np;             // SWAP - no lock!
 *   np.np = nil;
 *   closepgrp(opg);              // Decref old pgrp
 *   acquire();
 *
 * The critical window: between o->pgrp = np.np and closepgrp(opg),
 * another thread reading o->pgrp might see np.np (new, valid) or
 * still be using opg (which is being freed).
 *
 * Actually, the real danger is: the Dis virtual machine calls release()
 * before the pctl operation (line 809), allowing other emu threads to
 * run. If another thread has already read up->env->pgrp and cached it,
 * then after the swap, that cached pointer is stale.
 *
 * Note: In Inferno's threading model, only one Dis thread runs at a time
 * per virtual machine (cooperative scheduling with release()/acquire()).
 * However, multiple emu threads (for I/O, timers, etc.) can access the
 * Osenv concurrently.
 */

proctype sys_pctl_forkns(byte proc_id) {
    byte old_pg, new_pg;

    /* release() - allow concurrent access */
    /* (modeled by allowing interleaving) */

    /* np.np = newpgrp() */
    atomic {
        byte i;
        for (i : 0 .. (NUM_PGRPS - 1)) {
            if
            :: (pgrp_state[i] == PGRP_FREED) ->
                new_pg = i;
                pgrp_state[i] = PGRP_VALID;
                pgrp_refcount[i] = 1;
                break;
            :: else -> skip;
            fi
        }
    }

    /* pgrpcpy(np.np, o->pgrp) - copy mounts (simplified) */
    old_pg = process_pgrp[proc_id];
    /* Copy dot/slash from old to new */
    pgrp_dot[new_pg] = pgrp_dot[old_pg];
    pgrp_slash[new_pg] = pgrp_slash[old_pg];
    /* Incref channels for the copy */
    if
    :: (pgrp_dot[old_pg] < NUM_CHANS && chan_state[pgrp_dot[old_pg]] == CHAN_VALID) ->
        chan_refcount[pgrp_dot[old_pg]] = chan_refcount[pgrp_dot[old_pg]] + 1;
    :: else -> skip
    fi
    if
    :: (pgrp_slash[old_pg] < NUM_CHANS && chan_state[pgrp_slash[old_pg]] == CHAN_VALID) ->
        chan_refcount[pgrp_slash[old_pg]] = chan_refcount[pgrp_slash[old_pg]] + 1;
    :: else -> skip
    fi

    /* CRITICAL: Pointer swap without lock */
    /* opg = o->pgrp; o->pgrp = np.np; */
    process_pgrp[proc_id] = new_pg;

    /* closepgrp(opg) - decrement old pgrp refcount */
    pgrp_refcount[old_pg] = pgrp_refcount[old_pg] - 1;
    if
    :: (pgrp_refcount[old_pg] == 0) ->
        pgrp_state[old_pg] = PGRP_CLOSING;
        /* Free dot channel */
        if
        :: (pgrp_dot[old_pg] < NUM_CHANS) ->
            chan_refcount[pgrp_dot[old_pg]] = chan_refcount[pgrp_dot[old_pg]] - 1;
            if
            :: (chan_refcount[pgrp_dot[old_pg]] == 0) ->
                chan_state[pgrp_dot[old_pg]] = CHAN_FREED;
            :: else -> skip
            fi
        :: else -> skip
        fi
        pgrp_state[old_pg] = PGRP_FREED;
    :: else -> skip
    fi
}

/* ========== RACE 2: kchdir dot-writing ========== */

/*
 * Models kchdir() from sysfile.c:142-157:
 *
 *   c = namec(path, Atodir, 0, 0);
 *   pg = up->env->pgrp;
 *   cclose(pg->dot);       // STEP A: free old dot
 *   pg->dot = c;           // STEP B: assign new dot
 *
 * No lock held between steps A and B!
 */

proctype kchdir(byte proc_id; byte new_chan) {
    byte pg, old_dot;

    pg = process_pgrp[proc_id];

    /* Check pgrp is valid */
    assert(pg < NUM_PGRPS);
    if
    :: (pgrp_state[pg] != PGRP_VALID) -> goto done;
    :: else -> skip
    fi

    old_dot = pgrp_dot[pg];

    /* STEP A: cclose(pg->dot) - decrement refcount */
    if
    :: (old_dot < NUM_CHANS && chan_state[old_dot] == CHAN_VALID) ->
        chan_refcount[old_dot] = chan_refcount[old_dot] - 1;
        if
        :: (chan_refcount[old_dot] == 0) ->
            chan_state[old_dot] = CHAN_FREED;
        :: else -> skip
        fi
    :: else -> skip
    fi

    /* CRITICAL WINDOW: pg->dot points to potentially freed channel */
    /* Another thread reading pg->dot RIGHT NOW sees stale value */

    /* STEP B: pg->dot = c */
    pgrp_dot[pg] = new_chan;
    if
    :: (new_chan < NUM_CHANS && chan_state[new_chan] == CHAN_VALID) ->
        chan_refcount[new_chan] = chan_refcount[new_chan] + 1;
    :: else -> skip
    fi

done:
    skip;
}

/* ========== RACE 3: namec reading slash/dot ========== */

/*
 * Models namec() reading pg->slash or pg->dot (chan.c:1020-1058):
 *
 *   case '/':
 *     c = up->env->pgrp->slash;   // NO LOCK
 *     incref(&c->r);
 *     break;
 *   default:
 *     c = up->env->pgrp->dot;     // NO LOCK
 *     incref(&c->r);
 *     break;
 *
 * The read of pgrp->slash/dot is not protected.
 * Concurrent kchdir or Sys_pctl could be modifying these.
 */

proctype namec_reader(byte proc_id; bit use_slash) {
    byte pg, ch;

    /* Read pgrp pointer (could be stale if concurrent FORKNS) */
    pg = process_pgrp[proc_id];

    /* Check pgrp validity */
    if
    :: (pg >= NUM_PGRPS || pgrp_state[pg] != PGRP_VALID) ->
        /* USE-AFTER-FREE: reading a freed pgrp */
        if
        :: (pg < NUM_PGRPS && pgrp_state[pg] == PGRP_FREED) ->
            use_after_free_pgrp = true;
        :: else -> skip
        fi
        goto done;
    :: else -> skip
    fi

    /* Read slash or dot - NO LOCK */
    if
    :: (use_slash) -> ch = pgrp_slash[pg];
    :: else -> ch = pgrp_dot[pg];
    fi

    /* Check channel validity before incref */
    if
    :: (ch >= NUM_CHANS) -> goto done;
    :: else -> skip
    fi

    /* Try to incref - but channel might be freed! */
    if
    :: (chan_state[ch] == CHAN_FREED) ->
        /* USE-AFTER-FREE: trying to incref a freed channel */
        if
        :: (use_slash) -> use_after_free_slash = true;
        :: else -> use_after_free_dot = true;
        fi
    :: (chan_state[ch] == CHAN_VALID) ->
        chan_refcount[ch] = chan_refcount[ch] + 1;
        /* Use the channel for name resolution */
        skip;
        /* Done, decref */
        chan_refcount[ch] = chan_refcount[ch] - 1;
    :: else -> skip
    fi

done:
    skip;
}

/* ========== Test Scenarios ========== */

/*
 * Scenario 1: FORKNS races with namec
 * Process 0 calls Sys_pctl(FORKNS) while process 0's other
 * operations (via emu I/O threads) read pgrp->slash/dot.
 */
proctype test_forkns_race() {
    /* Initialize */
    atomic {
        pgrp_state[0] = PGRP_VALID;
        pgrp_refcount[0] = 2;  /* Shared between 2 "threads" */
        pgrp_dot[0] = 0;
        pgrp_slash[0] = 1;
        chan_state[0] = CHAN_VALID;
        chan_refcount[0] = 1;
        chan_state[1] = CHAN_VALID;
        chan_refcount[1] = 1;
        chan_state[2] = CHAN_VALID;
        chan_refcount[2] = 1;  /* New channel for new pgrp */
        chan_state[3] = CHAN_VALID;
        chan_refcount[3] = 1;
        process_pgrp[0] = 0;
        process_pgrp[1] = 0;
    }

    /* Run FORKNS and namec concurrently */
    run sys_pctl_forkns(0);
    run namec_reader(0, 0);     /* Read dot */
    run namec_reader(0, 1);     /* Read slash */
}

/*
 * Scenario 2: kchdir races with namec
 */
proctype test_kchdir_race() {
    atomic {
        pgrp_state[0] = PGRP_VALID;
        pgrp_refcount[0] = 1;
        pgrp_dot[0] = 0;
        pgrp_slash[0] = 1;
        chan_state[0] = CHAN_VALID;
        chan_refcount[0] = 1;
        chan_state[1] = CHAN_VALID;
        chan_refcount[1] = 1;
        chan_state[2] = CHAN_VALID;
        chan_refcount[2] = 1;
        process_pgrp[0] = 0;
        process_pgrp[1] = 0;
    }

    /* kchdir changes dot while namec reads it */
    run kchdir(0, 2);          /* Change dot to channel 2 */
    run namec_reader(0, 0);    /* Read dot */
}

init {
    byte i;
    /* Initialize all state */
    atomic {
        for (i : 0 .. (NUM_PGRPS - 1)) {
            pgrp_state[i] = PGRP_FREED;
            pgrp_refcount[i] = 0;
            pgrp_dot[i] = NUM_CHANS;  /* invalid */
            pgrp_slash[i] = NUM_CHANS;
        }
        for (i : 0 .. (NUM_CHANS - 1)) {
            chan_state[i] = CHAN_FREED;
            chan_refcount[i] = 0;
        }
        process_pgrp[0] = 0;
        process_pgrp[1] = 0;
    }

    /* Run test scenarios */
    if
    :: run test_forkns_race();
    :: run test_kchdir_race();
    fi
}

/*
 * LTL properties to check:
 *
 * If use_after_free_dot or use_after_free_pgrp becomes true,
 * it means we found a real race condition in the kernel code.
 *
 * NOTE: These races MAY be benign in Inferno's cooperative threading
 * model (only one Dis thread runs at a time). But they are real races
 * at the C level if multiple emu host threads are used.
 */

/* Check if any use-after-free was detected */
ltl no_use_after_free_dot   { [] (!use_after_free_dot) }
ltl no_use_after_free_pgrp  { [] (!use_after_free_pgrp) }
ltl no_use_after_free_slash { [] (!use_after_free_slash) }
