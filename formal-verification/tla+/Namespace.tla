---------------------------- MODULE Namespace ----------------------------
(***************************************************************************
 * Formal Specification of Inferno Kernel Namespace Isolation
 *
 * This module defines the core data structures and state for modeling
 * the Inferno kernel's process-specific namespace mechanism.
 *
 * Based on: emu/port/pgrp.c, emu/port/chan.c, emu/port/sysfile.c,
 *           emu/port/inferno.c (Sys_pctl)
 *
 * Key abstractions:
 *   - Pgrp: Process group containing a namespace (mount table)
 *   - Mount: Mount point entry mapping paths to channels
 *   - Chan: Channel (file handle) abstraction
 *   - RefCount: Reference counting for resource management
 *   - Slash/Dot: Root and working directory channels per namespace
 *
 * Revision: Rewritten to include history tracking for non-trivial
 * isolation verification, and namec/kchdir/pctl operations.
 ***************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

\* =========================================================================
\* CONSTANTS - Model parameters
\* =========================================================================

CONSTANTS
    MaxProcesses,       \* Maximum number of processes (e.g., 3)
    MaxPgrps,           \* Maximum number of process groups (e.g., 5)
    MaxChannels,        \* Maximum number of channels (e.g., 6)
    MaxPaths,           \* Maximum number of distinct paths (e.g., 3)
    MaxMountId          \* Maximum mount ID for bounded checking

\* Type aliases for readability
ProcessId == 1..MaxProcesses
PgrpId == 1..MaxPgrps
ChannelId == 1..MaxChannels
PathId == 1..MaxPaths
MountId == 1..MaxMountId
RefCountVal == 0..MaxProcesses + MaxPgrps + MaxChannels

\* =========================================================================
\* STATE VARIABLES
\* =========================================================================

VARIABLES
    \* Process state
    processes,          \* Set of active process IDs
    process_pgrp,       \* ProcessId -> PgrpId \cup {0} (which pgrp a process uses)

    \* Pgrp (namespace) state
    pgrp_exists,        \* PgrpId -> BOOLEAN (is this pgrp allocated)
    pgrp_refcount,      \* PgrpId -> Nat (reference count)

    \* Namespace (mount table) state - the core abstraction
    \* Each pgrp has its own mount table: PgrpId -> (PathId -> Set of ChannelId)
    mount_table,        \* PgrpId -> [PathId -> SUBSET ChannelId]

    \* Slash and dot channels per pgrp (models pg->slash, pg->dot)
    pgrp_slash,         \* PgrpId -> ChannelId \cup {0}
    pgrp_dot,           \* PgrpId -> ChannelId \cup {0}

    \* nodevs flag per pgrp
    pgrp_nodevs,        \* PgrpId -> BOOLEAN

    \* Channel state
    chan_exists,         \* ChannelId -> BOOLEAN
    chan_refcount,       \* ChannelId -> Nat

    \* Global counters
    next_pgrp_id,       \* Next available pgrp ID
    next_chan_id,        \* Next available channel ID

    \* =====================================================================
    \* HISTORY VARIABLES (for verification, not part of implementation)
    \* =====================================================================

    \* Records the mount table state at the moment of each pgrpcpy.
    \* copy_snapshot[child_pgid] = mount_table[parent_pgid] at copy time.
    copy_snapshot,      \* PgrpId -> [PathId -> SUBSET ChannelId]

    \* Records parent relationship
    pgrp_parent,        \* PgrpId -> PgrpId \cup {0}

    \* Tracks which (pgrp, path, chan) mounts were added AFTER a copy.
    \* post_copy_mounts[pgid] = set of <<path, cid>> mounted after pgid was
    \* either created fresh or received a copy.
    post_copy_mounts    \* PgrpId -> SUBSET (PathId \times ChannelId)

\* Tuple of all variables for temporal formulas
vars == <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
          mount_table, pgrp_slash, pgrp_dot, pgrp_nodevs,
          chan_exists, chan_refcount,
          next_pgrp_id, next_chan_id,
          copy_snapshot, pgrp_parent, post_copy_mounts>>

\* =========================================================================
\* TYPE INVARIANT
\* =========================================================================

TypeOK ==
    /\ processes \subseteq ProcessId
    /\ process_pgrp \in [ProcessId -> PgrpId \cup {0}]
    /\ pgrp_exists \in [PgrpId -> BOOLEAN]
    /\ pgrp_refcount \in [PgrpId -> RefCountVal]
    /\ mount_table \in [PgrpId -> [PathId -> SUBSET ChannelId]]
    /\ pgrp_slash \in [PgrpId -> ChannelId \cup {0}]
    /\ pgrp_dot \in [PgrpId -> ChannelId \cup {0}]
    /\ pgrp_nodevs \in [PgrpId -> BOOLEAN]
    /\ chan_exists \in [ChannelId -> BOOLEAN]
    /\ chan_refcount \in [ChannelId -> RefCountVal]
    /\ next_pgrp_id \in PgrpId \cup {MaxPgrps + 1}
    /\ next_chan_id \in ChannelId \cup {MaxChannels + 1}
    /\ copy_snapshot \in [PgrpId -> [PathId -> SUBSET ChannelId]]
    /\ pgrp_parent \in [PgrpId -> PgrpId \cup {0}]
    /\ post_copy_mounts \in [PgrpId -> SUBSET (PathId \X ChannelId)]

\* =========================================================================
\* HELPER FUNCTIONS
\* =========================================================================

\* Check if a pgrp is in use (has positive refcount)
PgrpInUse(pgid) == pgrp_exists[pgid] /\ pgrp_refcount[pgid] > 0

\* Check if a channel is in use
ChanInUse(cid) == chan_exists[cid] /\ chan_refcount[cid] > 0

\* Get all channels mounted anywhere in a pgrp's namespace
AllMountedChannels(pgid) ==
    UNION {mount_table[pgid][p] : p \in PathId}

\* Empty mount table constant
EmptyMountTable == [p \in PathId |-> {}]

\* Empty post-copy mount set
EmptyPostCopyMounts == {}

\* =========================================================================
\* INITIAL STATE
\* =========================================================================

Init ==
    \* No processes initially
    /\ processes = {}
    /\ process_pgrp = [p \in ProcessId |-> 0]

    \* No pgrps allocated
    /\ pgrp_exists = [pg \in PgrpId |-> FALSE]
    /\ pgrp_refcount = [pg \in PgrpId |-> 0]

    \* Empty mount tables
    /\ mount_table = [pg \in PgrpId |-> EmptyMountTable]

    \* No slash/dot channels
    /\ pgrp_slash = [pg \in PgrpId |-> 0]
    /\ pgrp_dot = [pg \in PgrpId |-> 0]
    /\ pgrp_nodevs = [pg \in PgrpId |-> FALSE]

    \* No channels allocated
    /\ chan_exists = [c \in ChannelId |-> FALSE]
    /\ chan_refcount = [c \in ChannelId |-> 0]

    \* IDs start at 1
    /\ next_pgrp_id = 1
    /\ next_chan_id = 1

    \* History variables
    /\ copy_snapshot = [pg \in PgrpId |-> EmptyMountTable]
    /\ pgrp_parent = [pg \in PgrpId |-> 0]
    /\ post_copy_mounts = [pg \in PgrpId |-> EmptyPostCopyMounts]

\* =========================================================================
\* CHANNEL OPERATIONS
\* =========================================================================

\* Allocate a new channel (models newchan())
AllocChannel ==
    /\ next_chan_id <= MaxChannels
    /\ LET cid == next_chan_id IN
        /\ chan_exists' = [chan_exists EXCEPT ![cid] = TRUE]
        /\ chan_refcount' = [chan_refcount EXCEPT ![cid] = 1]
        /\ next_chan_id' = next_chan_id + 1
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
                   mount_table, pgrp_slash, pgrp_dot, pgrp_nodevs,
                   next_pgrp_id, copy_snapshot, pgrp_parent, post_copy_mounts>>

\* Increment channel reference (models incref(&c->r))
\* Bounded to stay within RefCountVal (model-checking artifact; real refcounts
\* are bounded by the finite number of references in the system)
IncRefChannel(cid) ==
    /\ ChanInUse(cid)
    /\ chan_refcount[cid] < MaxProcesses + MaxPgrps + MaxChannels
    /\ chan_refcount' = [chan_refcount EXCEPT ![cid] = @ + 1]
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
                   mount_table, pgrp_slash, pgrp_dot, pgrp_nodevs, chan_exists,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent, post_copy_mounts>>

\* Decrement channel reference (models decref(&c->r) / cclose())
DecRefChannel(cid) ==
    /\ ChanInUse(cid)
    /\ chan_refcount' = [chan_refcount EXCEPT ![cid] = @ - 1]
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
                   mount_table, pgrp_slash, pgrp_dot, pgrp_nodevs, chan_exists,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent, post_copy_mounts>>

\* =========================================================================
\* PGRP OPERATIONS
\* =========================================================================

\* Create a new process group (models newpgrp())
NewPgrp ==
    /\ next_pgrp_id <= MaxPgrps
    /\ next_chan_id + 1 <= MaxChannels  \* Need channels for slash and dot
    /\ LET pgid == next_pgrp_id
           slash_cid == next_chan_id
           dot_cid == next_chan_id + 1
       IN
        /\ pgrp_exists' = [pgrp_exists EXCEPT ![pgid] = TRUE]
        /\ pgrp_refcount' = [pgrp_refcount EXCEPT ![pgid] = 1]
        /\ mount_table' = [mount_table EXCEPT ![pgid] = EmptyMountTable]
        /\ pgrp_slash' = [pgrp_slash EXCEPT ![pgid] = slash_cid]
        /\ pgrp_dot' = [pgrp_dot EXCEPT ![pgid] = dot_cid]
        /\ pgrp_nodevs' = [pgrp_nodevs EXCEPT ![pgid] = FALSE]
        /\ chan_exists' = [chan_exists EXCEPT ![slash_cid] = TRUE, ![dot_cid] = TRUE]
        /\ chan_refcount' = [chan_refcount EXCEPT ![slash_cid] = 1, ![dot_cid] = 1]
        /\ next_pgrp_id' = next_pgrp_id + 1
        /\ next_chan_id' = next_chan_id + 2
        \* History: fresh pgrp has no parent and no post-copy mounts
        /\ pgrp_parent' = [pgrp_parent EXCEPT ![pgid] = 0]
        /\ copy_snapshot' = [copy_snapshot EXCEPT ![pgid] = EmptyMountTable]
        /\ post_copy_mounts' = [post_copy_mounts EXCEPT ![pgid] = EmptyPostCopyMounts]
    /\ UNCHANGED <<processes, process_pgrp>>

\* Close/decrement pgrp reference (models closepgrp())
\* When refcount hits 0, frees all mounts
ClosePgrp(pgid) ==
    /\ PgrpInUse(pgid)
    /\ pgrp_refcount' = [pgrp_refcount EXCEPT ![pgid] = @ - 1]
    /\ IF pgrp_refcount[pgid] = 1  \* will become 0
       THEN
         /\ mount_table' = [mount_table EXCEPT ![pgid] = EmptyMountTable]
         /\ pgrp_slash' = [pgrp_slash EXCEPT ![pgid] = 0]
         /\ pgrp_dot' = [pgrp_dot EXCEPT ![pgid] = 0]
       ELSE
         /\ UNCHANGED <<mount_table, pgrp_slash, pgrp_dot>>
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_nodevs,
                   chan_exists, chan_refcount,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent, post_copy_mounts>>

\* =========================================================================
\* NAMESPACE COPY OPERATION (pgrpcpy - critical for isolation)
\* =========================================================================

(*
 * Models pgrpcpy(to, from) from pgrp.c
 *
 * Key property: Creates a DEEP COPY of the namespace.
 * The new pgrp gets its own mount table that is initially
 * identical to the parent but is independent thereafter.
 *
 * In the actual implementation:
 *   - wlock(&from->ns) held during copy
 *   - New Mhead structures are allocated for each mount point
 *   - New Mount structures are allocated for each mount entry
 *   - Channels are SHARED (incref'd) but mount structures are copied
 *   - slash and dot are cloned via cclone()
 *   - nodevs flag is copied
 *
 * History: We record a snapshot of the parent's mount table at copy time
 * and reset the child's post_copy_mounts to empty.
 *)
PgrpCopy(from_pgid, to_pgid) ==
    /\ PgrpInUse(from_pgid)
    /\ pgrp_exists[to_pgid]
    /\ pgrp_refcount[to_pgid] > 0
    /\ from_pgid # to_pgid
    \* Copy mount table from 'from' to 'to'
    /\ mount_table' = [mount_table EXCEPT
                       ![to_pgid] = mount_table[from_pgid]]
    \* Copy slash, dot, nodevs
    /\ pgrp_slash' = [pgrp_slash EXCEPT ![to_pgid] = pgrp_slash[from_pgid]]
    /\ pgrp_dot' = [pgrp_dot EXCEPT ![to_pgid] = pgrp_dot[from_pgid]]
    /\ pgrp_nodevs' = [pgrp_nodevs EXCEPT ![to_pgid] = pgrp_nodevs[from_pgid]]
    \* History: record snapshot of parent's mount table at copy time
    /\ copy_snapshot' = [copy_snapshot EXCEPT ![to_pgid] = mount_table[from_pgid]]
    /\ pgrp_parent' = [pgrp_parent EXCEPT ![to_pgid] = from_pgid]
    \* Reset post-copy mounts for the child (fresh start)
    /\ post_copy_mounts' = [post_copy_mounts EXCEPT ![to_pgid] = EmptyPostCopyMounts]
    \* In real impl, channels get incref'd for the copy
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
                   chan_exists, chan_refcount,
                   next_pgrp_id, next_chan_id>>

\* =========================================================================
\* MOUNT/UNMOUNT OPERATIONS
\* =========================================================================

(*
 * Models cmount(new, old, flag, spec) from chan.c
 *
 * Adds channel 'cid' to the mount table at 'path' for pgrp 'pgid'.
 * This is the operation that MUST NOT cross namespace boundaries.
 *
 * Lock sequence: wlock(pg->ns), wlock(m->lock), wunlock(pg->ns), ..., wunlock(m->lock)
 *)
Mount(pgid, path, cid) ==
    /\ PgrpInUse(pgid)
    /\ ChanInUse(cid)
    /\ path \in PathId
    \* Add channel to mount table at path
    /\ mount_table' = [mount_table EXCEPT
                       ![pgid][path] = @ \cup {cid}]
    \* History: record this as a post-copy mount
    /\ post_copy_mounts' = [post_copy_mounts EXCEPT
                            ![pgid] = @ \cup {<<path, cid>>}]
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
                   pgrp_slash, pgrp_dot, pgrp_nodevs,
                   chan_exists, chan_refcount,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent>>

(*
 * Models cunmount(mnt, mounted) from chan.c
 *
 * Removes channel 'cid' from mount table at 'path' for pgrp 'pgid'.
 *)
Unmount(pgid, path, cid) ==
    /\ PgrpInUse(pgid)
    /\ cid \in mount_table[pgid][path]
    \* Remove channel from mount table
    /\ mount_table' = [mount_table EXCEPT
                       ![pgid][path] = @ \ {cid}]
    \* History: record this as a post-copy change
    /\ post_copy_mounts' = [post_copy_mounts EXCEPT
                            ![pgid] = @ \cup {<<path, cid>>}]
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
                   pgrp_slash, pgrp_dot, pgrp_nodevs,
                   chan_exists, chan_refcount,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent>>

\* =========================================================================
\* NAME RESOLUTION (models namec() from chan.c)
\* =========================================================================

(*
 * Models the start of namec() - reading slash or dot to begin resolution.
 *
 * In the real implementation (chan.c:1020-1058):
 *   case '/': c = up->env->pgrp->slash; incref(&c->r); break;
 *   default:  c = up->env->pgrp->dot;  incref(&c->r); break;
 *
 * CRITICAL: These reads happen WITHOUT any lock on pg->ns.
 * The pgrp pointer itself is read from up->env->pgrp without locks.
 *
 * This is modeled as a read of pgrp_slash or pgrp_dot.
 * For verification, we check that the returned channel is valid.
 *)
NameResolve(pid, path) ==
    /\ pid \in processes
    /\ LET pgid == process_pgrp[pid] IN
        /\ PgrpInUse(pgid)
        /\ path \in PathId
        \* Read slash or dot (nondeterministic choice models '/' vs relative)
        /\ \/ pgrp_slash[pgid] # 0  \* absolute path
           \/ pgrp_dot[pgid] # 0    \* relative path
        \* Name resolution then walks through mount table via findmount/domount
        \* This is a read-only operation on the mount table (rlock held)
        \* No state change - the important thing is modeling the access pattern
    /\ UNCHANGED vars

(*
 * Models kchdir() from sysfile.c:142-157
 *
 *   pg = up->env->pgrp;
 *   cclose(pg->dot);
 *   pg->dot = c;
 *
 * CRITICAL: Writes pg->dot WITHOUT any lock.
 * If concurrent namec() reads pg->dot between cclose and assignment,
 * it could use a freed channel.
 *
 * We model this as updating pgrp_dot for the process's pgrp.
 *)
ChangeDir(pid, new_dot_cid) ==
    /\ pid \in processes
    /\ ChanInUse(new_dot_cid)
    /\ LET pgid == process_pgrp[pid] IN
        /\ PgrpInUse(pgid)
        /\ pgrp_dot' = [pgrp_dot EXCEPT ![pgid] = new_dot_cid]
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
                   mount_table, pgrp_slash, pgrp_nodevs,
                   chan_exists, chan_refcount,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent, post_copy_mounts>>

\* =========================================================================
\* PROCESS OPERATIONS
\* =========================================================================

\* Create a new process with a new pgrp
CreateProcess ==
    /\ \E pid \in ProcessId :
        /\ pid \notin processes
        /\ next_pgrp_id <= MaxPgrps
        /\ next_chan_id + 1 <= MaxChannels
        /\ LET pgid == next_pgrp_id
               slash_cid == next_chan_id
               dot_cid == next_chan_id + 1
           IN
            /\ processes' = processes \cup {pid}
            /\ process_pgrp' = [process_pgrp EXCEPT ![pid] = pgid]
            /\ pgrp_exists' = [pgrp_exists EXCEPT ![pgid] = TRUE]
            /\ pgrp_refcount' = [pgrp_refcount EXCEPT ![pgid] = 1]
            /\ mount_table' = [mount_table EXCEPT ![pgid] = EmptyMountTable]
            /\ pgrp_slash' = [pgrp_slash EXCEPT ![pgid] = slash_cid]
            /\ pgrp_dot' = [pgrp_dot EXCEPT ![pgid] = dot_cid]
            /\ pgrp_nodevs' = [pgrp_nodevs EXCEPT ![pgid] = FALSE]
            /\ chan_exists' = [chan_exists EXCEPT ![slash_cid] = TRUE, ![dot_cid] = TRUE]
            /\ chan_refcount' = [chan_refcount EXCEPT ![slash_cid] = 1, ![dot_cid] = 1]
            /\ next_pgrp_id' = next_pgrp_id + 1
            /\ next_chan_id' = next_chan_id + 2
            \* History
            /\ pgrp_parent' = [pgrp_parent EXCEPT ![pgid] = 0]
            /\ copy_snapshot' = [copy_snapshot EXCEPT ![pgid] = EmptyMountTable]
            /\ post_copy_mounts' = [post_copy_mounts EXCEPT ![pgid] = EmptyPostCopyMounts]

(*
 * Fork with FORKNS (models Sys_pctl with Sys_FORKNS flag)
 *
 * From inferno.c:869-876:
 *   np.np = newpgrp();
 *   pgrpcpy(np.np, o->pgrp);
 *   opg = o->pgrp;
 *   o->pgrp = np.np;      <- pointer swap, no lock
 *   np.np = nil;
 *   closepgrp(opg);
 *
 * The process gets a NEW pgrp with a COPY of the parent's namespace.
 *)
ForkWithForkNS(parent_pid) ==
    /\ parent_pid \in processes
    /\ next_pgrp_id <= MaxPgrps
    /\ next_chan_id + 1 <= MaxChannels
    /\ LET parent_pgid == process_pgrp[parent_pid]
           child_pgid == next_pgrp_id
           slash_cid == next_chan_id
           dot_cid == next_chan_id + 1
       IN
        /\ PgrpInUse(parent_pgid)
        \* Create new pgrp
        /\ pgrp_exists' = [pgrp_exists EXCEPT ![child_pgid] = TRUE]
        /\ pgrp_refcount' = [pgrp_refcount EXCEPT
                             ![child_pgid] = 1,
                             ![parent_pgid] = pgrp_refcount[parent_pgid] - 1]
        \* Copy mount table (pgrpcpy semantics)
        /\ mount_table' = [mount_table EXCEPT
                           ![child_pgid] = mount_table[parent_pgid]]
        \* Copy slash/dot/nodevs
        /\ pgrp_slash' = [pgrp_slash EXCEPT ![child_pgid] = pgrp_slash[parent_pgid]]
        /\ pgrp_dot' = [pgrp_dot EXCEPT ![child_pgid] = pgrp_dot[parent_pgid]]
        /\ pgrp_nodevs' = [pgrp_nodevs EXCEPT ![child_pgid] = pgrp_nodevs[parent_pgid]]
        \* Allocate channels for slash/dot clones
        /\ chan_exists' = [chan_exists EXCEPT ![slash_cid] = TRUE, ![dot_cid] = TRUE]
        /\ chan_refcount' = [chan_refcount EXCEPT ![slash_cid] = 1, ![dot_cid] = 1]
        \* Swap the process's pgrp pointer
        /\ process_pgrp' = [process_pgrp EXCEPT ![parent_pid] = child_pgid]
        /\ next_pgrp_id' = next_pgrp_id + 1
        /\ next_chan_id' = next_chan_id + 2
        \* History: snapshot parent's mount table for the child
        /\ copy_snapshot' = [copy_snapshot EXCEPT ![child_pgid] = mount_table[parent_pgid]]
        /\ pgrp_parent' = [pgrp_parent EXCEPT ![child_pgid] = parent_pgid]
        /\ post_copy_mounts' = [post_copy_mounts EXCEPT ![child_pgid] = EmptyPostCopyMounts]
    /\ UNCHANGED <<processes>>

(*
 * Fork with NEWNS (models Sys_pctl with Sys_NEWNS flag)
 *
 * From inferno.c:855-867:
 *   np.np = newpgrp();
 *   np.np->dot = cclone(dot);
 *   np.np->slash = cclone(dot);  <- NOTE: slash is set to dot, not parent slash
 *   np.np->nodevs = o->pgrp->nodevs;
 *   o->pgrp = np.np;
 *   closepgrp(opg);
 *
 * The process gets a completely EMPTY namespace (no mounts copied).
 *)
ForkWithNewNS(parent_pid) ==
    /\ parent_pid \in processes
    /\ next_pgrp_id <= MaxPgrps
    /\ next_chan_id + 1 <= MaxChannels
    /\ LET parent_pgid == process_pgrp[parent_pid]
           child_pgid == next_pgrp_id
           slash_cid == next_chan_id
           dot_cid == next_chan_id + 1
       IN
        /\ PgrpInUse(parent_pgid)
        \* Create new pgrp with empty mount table
        /\ pgrp_exists' = [pgrp_exists EXCEPT ![child_pgid] = TRUE]
        /\ pgrp_refcount' = [pgrp_refcount EXCEPT
                             ![child_pgid] = 1,
                             ![parent_pgid] = pgrp_refcount[parent_pgid] - 1]
        /\ mount_table' = [mount_table EXCEPT ![child_pgid] = EmptyMountTable]
        \* NEWNS: slash=cclone(dot), dot=cclone(dot) (from parent)
        /\ pgrp_slash' = [pgrp_slash EXCEPT ![child_pgid] = slash_cid]
        /\ pgrp_dot' = [pgrp_dot EXCEPT ![child_pgid] = dot_cid]
        /\ pgrp_nodevs' = [pgrp_nodevs EXCEPT ![child_pgid] = pgrp_nodevs[parent_pgid]]
        /\ chan_exists' = [chan_exists EXCEPT ![slash_cid] = TRUE, ![dot_cid] = TRUE]
        /\ chan_refcount' = [chan_refcount EXCEPT ![slash_cid] = 1, ![dot_cid] = 1]
        \* Swap the process's pgrp pointer
        /\ process_pgrp' = [process_pgrp EXCEPT ![parent_pid] = child_pgid]
        /\ next_pgrp_id' = next_pgrp_id + 1
        /\ next_chan_id' = next_chan_id + 2
        \* History: empty snapshot, no parent for isolation tracking
        /\ copy_snapshot' = [copy_snapshot EXCEPT ![child_pgid] = EmptyMountTable]
        /\ pgrp_parent' = [pgrp_parent EXCEPT ![child_pgid] = 0]
        /\ post_copy_mounts' = [post_copy_mounts EXCEPT ![child_pgid] = EmptyPostCopyMounts]
    /\ UNCHANGED <<processes>>

(*
 * Fork a child process that inherits the same pgrp (SHARED namespace)
 *)
ForkWithSharedNS(parent_pid) ==
    /\ parent_pid \in processes
    /\ \E child_pid \in ProcessId :
        /\ child_pid \notin processes
        /\ LET pgid == process_pgrp[parent_pid] IN
            /\ PgrpInUse(pgid)
            /\ processes' = processes \cup {child_pid}
            /\ process_pgrp' = [process_pgrp EXCEPT ![child_pid] = pgid]
            /\ pgrp_refcount' = [pgrp_refcount EXCEPT ![pgid] = @ + 1]
    /\ UNCHANGED <<pgrp_exists, mount_table, pgrp_slash, pgrp_dot, pgrp_nodevs,
                   chan_exists, chan_refcount,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent, post_copy_mounts>>

\* Set nodevs flag (models Sys_pctl with Sys_NODEVS)
SetNoDevs(pid) ==
    /\ pid \in processes
    /\ LET pgid == process_pgrp[pid] IN
        /\ PgrpInUse(pgid)
        /\ pgrp_nodevs' = [pgrp_nodevs EXCEPT ![pgid] = TRUE]
    /\ UNCHANGED <<processes, process_pgrp, pgrp_exists, pgrp_refcount,
                   mount_table, pgrp_slash, pgrp_dot,
                   chan_exists, chan_refcount,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent, post_copy_mounts>>

\* Terminate a process
TerminateProcess(pid) ==
    /\ pid \in processes
    /\ LET pgid == process_pgrp[pid] IN
        /\ processes' = processes \ {pid}
        /\ process_pgrp' = [process_pgrp EXCEPT ![pid] = 0]
        /\ pgrp_refcount' = [pgrp_refcount EXCEPT ![pgid] = @ - 1]
        /\ IF pgrp_refcount[pgid] = 1
           THEN
             /\ mount_table' = [mount_table EXCEPT ![pgid] = EmptyMountTable]
             /\ pgrp_slash' = [pgrp_slash EXCEPT ![pgid] = 0]
             /\ pgrp_dot' = [pgrp_dot EXCEPT ![pgid] = 0]
           ELSE
             /\ UNCHANGED <<mount_table, pgrp_slash, pgrp_dot>>
    /\ UNCHANGED <<pgrp_exists, pgrp_nodevs,
                   chan_exists, chan_refcount,
                   next_pgrp_id, next_chan_id,
                   copy_snapshot, pgrp_parent, post_copy_mounts>>

\* =========================================================================
\* NEXT STATE RELATION
\* =========================================================================

Next ==
    \/ CreateProcess
    \/ \E pid \in processes : ForkWithForkNS(pid)
    \/ \E pid \in processes : ForkWithNewNS(pid)
    \/ \E pid \in processes : ForkWithSharedNS(pid)
    \/ \E pid \in processes : TerminateProcess(pid)
    \/ \E pid \in processes : SetNoDevs(pid)
    \/ AllocChannel
    \/ \E cid \in ChannelId : ChanInUse(cid) /\ IncRefChannel(cid)
    \/ \E cid \in ChannelId : ChanInUse(cid) /\ DecRefChannel(cid)
    \/ \E pgid \in PgrpId, path \in PathId, cid \in ChannelId :
        PgrpInUse(pgid) /\ ChanInUse(cid) /\ Mount(pgid, path, cid)
    \/ \E pgid \in PgrpId, path \in PathId, cid \in ChannelId :
        PgrpInUse(pgid) /\ cid \in mount_table[pgid][path] /\ Unmount(pgid, path, cid)
    \/ \E pid \in processes, cid \in ChannelId :
        ChanInUse(cid) /\ ChangeDir(pid, cid)

\* Fairness
Fairness == WF_vars(Next)

Spec == Init /\ [][Next]_vars /\ Fairness

=============================================================================
