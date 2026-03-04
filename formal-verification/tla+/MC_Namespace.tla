--------------------------- MODULE MC_Namespace ---------------------------
(***************************************************************************
 * Model Checking Configuration for Namespace Specification
 *
 * This module configures the TLC model checker with appropriate
 * constants and properties to verify.
 *
 * Usage:
 *   tlc MC_Namespace.tla -config MC_Namespace.cfg
 *
 * Or with the TLA+ Toolbox, select this module as the model.
 ***************************************************************************)

EXTENDS Namespace, NamespaceProperties, IsolationProof, TLC

\* =========================================================================
\* MODEL CONSTANTS
\* =========================================================================

CONSTANTS
    MC_MaxProcesses,
    MC_MaxPgrps,
    MC_MaxChannels,
    MC_MaxPaths,
    MC_MaxMountId

\* Bind the model constants to the specification constants
MaxProcesses == MC_MaxProcesses
MaxPgrps == MC_MaxPgrps
MaxChannels == MC_MaxChannels
MaxPaths == MC_MaxPaths
MaxMountId == MC_MaxMountId

\* =========================================================================
\* STATE CONSTRAINT
\* =========================================================================

\* Limit state space for finite model checking
StateConstraint ==
    /\ Cardinality(processes) <= MC_MaxProcesses
    /\ next_pgrp_id <= MC_MaxPgrps + 1
    /\ next_chan_id <= MC_MaxChannels + 1

\* =========================================================================
\* ACTION CONSTRAINT
\* =========================================================================

ActionConstraint ==
    /\ next_pgrp_id' <= MC_MaxPgrps + 1
    /\ next_chan_id' <= MC_MaxChannels + 1

\* =========================================================================
\* INVARIANTS TO CHECK
\* =========================================================================

\* Core type safety
INVARIANT_TypeOK == TypeOK

\* Primary safety invariant
INVARIANT_Safety == SafetyInvariant

\* Full correctness including isolation
INVARIANT_Full == FullCorrectness

\* Non-trivial isolation properties
INVARIANT_Isolation == NamespaceIsolation
INVARIANT_IsolationTheorem == NamespaceIsolationTheorem
INVARIANT_NonPropagation == UnilateralMountNonPropagation
INVARIANT_CopyFidelity == CopyFidelity
INVARIANT_PostCopySoundness == PostCopyMountsSound
INVARIANT_NoViolation == NoIsolationViolation

\* =========================================================================
\* PROPERTIES TO CHECK
\* =========================================================================

\* Mount locality (temporal)
PROPERTY_MountLocality == MountLocalityProperty

\* Progress
PROPERTY_Progress == Progress

\* =========================================================================
\* SYMMETRY OPTIMIZATION
\* =========================================================================

\* Process IDs are symmetric (any permutation is equivalent)
ProcessSymmetry == Permutations(1..MC_MaxProcesses)

\* Channel IDs are symmetric
ChannelSymmetry == Permutations(1..MC_MaxChannels)

\* Path IDs are symmetric
PathSymmetry == Permutations(1..MC_MaxPaths)

\* =========================================================================
\* DEBUG HELPERS
\* =========================================================================

\* Alias for printing state in error traces
Alias == [
    procs |-> processes,
    proc_pgrp |-> process_pgrp,
    pgrps |-> {pg \in PgrpId : pgrp_exists[pg]},
    pgrp_refs |-> [pg \in {p \in PgrpId : pgrp_exists[p]} |-> pgrp_refcount[pg]],
    mounts |-> [pg \in {p \in PgrpId : pgrp_exists[p]} |->
                    [path \in PathId |-> mount_table[pg][path]]],
    slash |-> [pg \in {p \in PgrpId : pgrp_exists[p]} |-> pgrp_slash[pg]],
    dot |-> [pg \in {p \in PgrpId : pgrp_exists[p]} |-> pgrp_dot[pg]],
    parents |-> [pg \in {p \in PgrpId : pgrp_exists[p]} |-> pgrp_parent[pg]],
    post_mounts |-> [pg \in {p \in PgrpId : pgrp_exists[p]} |-> post_copy_mounts[pg]],
    snapshots |-> [pg \in {p \in PgrpId : pgrp_exists[p] /\ pgrp_parent[p] # 0} |->
                      copy_snapshot[pg]],
    chans |-> {c \in ChannelId : chan_exists[c]},
    chan_refs |-> [c \in {ch \in ChannelId : chan_exists[ch]} |-> chan_refcount[c]]
]

=============================================================================
