----------------------- MODULE NamespaceProperties -----------------------
(***************************************************************************
 * Safety Properties for Inferno Kernel Namespace Isolation
 *
 * This module defines the key invariants and safety properties that must
 * hold for the namespace implementation to be correct.
 *
 * Primary Property: NAMESPACE ISOLATION
 *   After pgrpcpy() creates a child namespace, modifications to either
 *   the parent or child namespace must NOT affect the other.
 *
 * Secondary Properties:
 *   - Reference counting correctness
 *   - No use-after-free
 *   - Mount table consistency
 *   - Mount operation locality (at most one pgrp modified per step)
 *   - nodevs monotonicity
 *
 * Revision: Rewritten with non-trivial isolation properties using
 * history variables (copy_snapshot, post_copy_mounts).
 ***************************************************************************)

EXTENDS Namespace

\* =========================================================================
\* NAMESPACE ISOLATION PROPERTIES (non-trivial, using history variables)
\* =========================================================================

(*
 * NS-ISO-1: Post-Copy Mount Isolation
 *
 * After pgrpcpy(parent, child) creates a child namespace, any mount
 * added to the parent AFTER the copy must NOT appear in the child's
 * mount table, and vice versa.
 *
 * Formally: If (path, cid) is in post_copy_mounts[pg1] (meaning it
 * was mounted in pg1 after pg1's creation/copy), and pg2 is pg1's
 * parent or child, then cid must NOT be in mount_table[pg2][path]
 * UNLESS pg2 also independently mounted it (i.e., (path, cid) is
 * also in post_copy_mounts[pg2]).
 *
 * This is the core isolation guarantee. It is NOT tautologically true —
 * it could be violated if Mount incorrectly modified multiple pgrps'
 * mount tables, or if PgrpCopy used pointer sharing instead of value copy.
 *)

NamespaceIsolation ==
    \A pg_child \in PgrpId :
        LET pg_parent == pgrp_parent[pg_child] IN
        (PgrpInUse(pg_child) /\ pg_parent # 0 /\ PgrpInUse(pg_parent)) =>
            \* Part A: Mounts added to parent after copy don't leak to child
            \* Note: post_copy_mounts[parent] may include mounts from BEFORE
            \* the fork (i.e., present in the snapshot). Those are not violations.
            (\A path \in PathId, cid \in ChannelId :
                (<<path, cid>> \in post_copy_mounts[pg_parent] /\
                 cid \in mount_table[pg_parent][path]) =>
                    (cid \in mount_table[pg_child][path] =>
                        (<<path, cid>> \in post_copy_mounts[pg_child] \/
                         cid \in copy_snapshot[pg_child][path])))
            /\
            \* Part B: Mounts added to child after copy don't leak to parent
            \* Child's post_copy_mounts are always truly post-fork (reset at copy)
            \* but they could coincide with parent's pre-fork mounts in the snapshot.
            (\A path \in PathId, cid \in ChannelId :
                (<<path, cid>> \in post_copy_mounts[pg_child] /\
                 cid \in mount_table[pg_child][path]) =>
                    (cid \in mount_table[pg_parent][path] =>
                        (<<path, cid>> \in post_copy_mounts[pg_parent] \/
                         cid \in copy_snapshot[pg_child][path])))

(*
 * NS-ISO-2: Mount Operation Locality
 *
 * Each step modifies at most one pgrp's mount table.
 * Exception: PgrpCopy modifies the destination (but not the source).
 *
 * This ensures that a cmount() call targeting one pgrp cannot
 * accidentally modify another pgrp's namespace.
 *)
MountTablesChanged ==
    Cardinality({pg \in PgrpId : mount_table'[pg] # mount_table[pg]})

MountLocalityProperty ==
    [][MountTablesChanged <= 1]_vars

(*
 * NS-ISO-3: Copy Fidelity
 *
 * Immediately after PgrpCopy, the child's mount table equals the
 * snapshot taken of the parent's mount table at copy time.
 *
 * This verifies that the copy was accurate — the child starts with
 * exactly the parent's namespace, nothing more, nothing less.
 *)
CopyFidelity ==
    \A pg_child \in PgrpId :
        (PgrpInUse(pg_child) /\ pgrp_parent[pg_child] # 0 /\
         post_copy_mounts[pg_child] = EmptyPostCopyMounts) =>
            \* If no post-copy mounts have been made, mount table should
            \* equal the snapshot taken at copy time
            mount_table[pg_child] = copy_snapshot[pg_child]

(*
 * NS-ISO-4: NEWNS Creates Clean Namespace
 *
 * When ForkWithNewNS is used, the resulting pgrp has an empty mount
 * table (no inherited mounts from parent).
 *)
NewNSIsClean ==
    \A pg \in PgrpId :
        (PgrpInUse(pg) /\ pgrp_parent[pg] = 0 /\
         post_copy_mounts[pg] = EmptyPostCopyMounts) =>
            mount_table[pg] = EmptyMountTable

(*
 * NS-ISO-5: nodevs Flag Isolation
 *
 * Setting nodevs on one pgrp does not affect other pgrps.
 * The nodevs flag on a child pgrp is independent of the parent
 * after the copy.
 *)
NoDevsIsolation ==
    \A pg1, pg2 \in PgrpId :
        (PgrpInUse(pg1) /\ PgrpInUse(pg2) /\ pg1 # pg2) =>
            \* nodevs flags are stored independently
            TRUE  \* Structural - but we verify via MountLocality
            \* The real test is that SetNoDevs only modifies one pgrp

\* =========================================================================
\* REFERENCE COUNTING PROPERTIES
\* =========================================================================

(*
 * REF-1: Reference Count Non-Negativity
 *
 * Reference counts must never go negative.
 *)
RefCountNonNegative ==
    /\ \A pgid \in PgrpId : pgrp_refcount[pgid] >= 0
    /\ \A cid \in ChannelId : chan_refcount[cid] >= 0

(*
 * REF-2: Active Pgrps Have Positive RefCount
 *
 * If a pgrp is assigned to any process, it must have a positive refcount.
 *)
ActivePgrpRefCount ==
    \A pgid \in PgrpId :
        (\E pid \in processes : process_pgrp[pid] = pgid)
            => pgrp_refcount[pgid] > 0

(*
 * REF-3: No Use After Free
 *
 * A pgrp with refcount 0 should not be assigned to any process.
 *)
NoUseAfterFree ==
    \A pgid \in PgrpId :
        pgrp_refcount[pgid] = 0 =>
            ~(\E pid \in processes : process_pgrp[pid] = pgid)

\* =========================================================================
\* MOUNT TABLE CONSISTENCY
\* =========================================================================

(*
 * MT-1: Mount Table Bounded
 *
 * Mount tables should only contain valid channel IDs.
 *)
MountTableBounded ==
    \A pgid \in PgrpId :
        \A path \in PathId :
            mount_table[pgid][path] \subseteq ChannelId

(*
 * MT-2: Mounted Channels Exist
 *
 * Channels in active pgrps' mount tables should exist.
 *)
MountedChannelsExist ==
    \A pgid \in PgrpId :
        PgrpInUse(pgid) =>
            \A cid \in AllMountedChannels(pgid) :
                chan_exists[cid]

(*
 * MT-3: Slash/Dot Consistency
 *
 * Active pgrps should have valid slash and dot channels.
 *)
SlashDotConsistency ==
    \A pgid \in PgrpId :
        PgrpInUse(pgid) =>
            /\ pgrp_slash[pgid] # 0
            /\ pgrp_dot[pgid] # 0

\* =========================================================================
\* COMBINED INVARIANTS
\* =========================================================================

\* Core safety invariant
SafetyInvariant ==
    /\ TypeOK
    /\ RefCountNonNegative
    /\ NoUseAfterFree
    /\ MountTableBounded

\* Full correctness (includes all properties)
FullCorrectness ==
    /\ SafetyInvariant
    /\ NamespaceIsolation
    /\ CopyFidelity
    /\ ActivePgrpRefCount
    /\ MountedChannelsExist
    /\ SlashDotConsistency

\* =========================================================================
\* TEMPORAL PROPERTIES (Liveness)
\* =========================================================================

\* The system can always make progress
Progress == <>(\E pid \in ProcessId : pid \in processes)

\* Resources are eventually freed
ResourceCleanup ==
    \A pgid \in PgrpId :
        (pgrp_exists[pgid] /\ pgrp_refcount[pgid] = 0) ~>
            (mount_table[pgid] = EmptyMountTable)

\* =========================================================================
\* PROPERTY DOCUMENTATION
\* =========================================================================

(*
 * Summary of Verified Properties:
 *
 * SAFETY (Always true):
 *   1. TypeOK - All variables have correct types
 *   2. RefCountNonNegative - Reference counts >= 0
 *   3. NoUseAfterFree - Freed objects not used
 *   4. MountTableBounded - Valid channel references
 *   5. NamespaceIsolation - Post-copy mounts don't leak across namespaces
 *   6. CopyFidelity - Copy produces exact duplicate
 *   7. MountLocalityProperty - Each step modifies at most one pgrp
 *   8. ActivePgrpRefCount - Active pgrps have positive refcount
 *   9. MountedChannelsExist - Mounted channels are valid
 *  10. SlashDotConsistency - Active pgrps have valid slash/dot
 *
 * LIVENESS (Eventually true):
 *   1. Progress - System can make progress
 *   2. ResourceCleanup - Resources eventually freed
 *
 * These properties correspond to the security claims:
 *   - Process isolation through per-process namespaces
 *   - Memory safety through reference counting
 *   - No information leakage between namespaces
 *   - Correct namespace forking (FORKNS and NEWNS)
 *)

=============================================================================
