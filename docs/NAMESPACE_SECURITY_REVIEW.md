# Veltro Agent Namespace Security Model: Technical Review Document

## Executive Summary

Veltro is an AI agent for Inferno OS where **namespace IS the capability system**. This document compares two approaches for implementing namespace-based security when spawning subagents with restricted capabilities.

**Approaches under consideration:**
1. **NEWNS + Build Up**: Start with empty namespace, construct only what's granted
2. **FORKNS + Unmount**: Copy parent's namespace, remove what's not granted

We seek expert review on security properties, implementation feasibility, and potential bypasses.

---

## 1. System Context

### 1.1 What is Veltro?

Veltro is an AI agent that runs inside Inferno OS. It:
- Receives tasks from users or parent agents
- Has access to tools (read, write, list, find, search, edit, exec, spawn)
- Can spawn subagents with **attenuated capabilities**
- Interacts with an LLM to decide actions

### 1.2 The Capability Model

```
User/System creates Agent A:
  tools:     [read, write, list, find, search, edit, exec, spawn]
  paths:     [/appl, /usr, /tmp]
  shellcmds: [cat, ls, rm, mk, limbo, grep]

Agent A spawns Agent B:
  tools:     [read, list, exec]        # subset of A's tools
  paths:     [/appl/veltro]            # subset of A's paths
  shellcmds: [cat, ls]                 # subset of A's shellcmds

Agent B spawns Agent C:
  tools:     [read, list]              # subset of B's tools
  paths:     [/appl/veltro/tools]      # subset of B's paths
  shellcmds: []                        # no exec, so irrelevant
```

**Invariant**: A child's capabilities are always ≤ parent's capabilities.

### 1.3 Three Capability Dimensions

| Dimension | What it controls | Enforcement mechanism |
|-----------|------------------|----------------------|
| **tools** | Which Veltro tools are available | tools9p synthetic filesystem |
| **paths** | Which filesystem paths are accessible | *Under discussion* |
| **shellcmds** | Which shell commands `exec` can run | /dis directory contents |

Tools and shellcmds are already enforced at namespace level. **Paths are the focus of this review.**

---

## 2. Design Goals

### 2.1 Primary Goals

1. **Structural enforcement**: Security enforced by namespace structure, not policy checks
2. **Truthful environment**: Agent sees only what it can use; no "access denied" on visible paths
3. **Capability attenuation**: Children can only have ≤ parent's capabilities
4. **No bypass**: No mechanism for agent to escape its namespace
5. **Simplicity**: Simpler systems have fewer bugs

### 2.2 Non-Goals

1. **Resource limits**: CPU, memory, time limits (future work)
2. **Network isolation**: Network access control (future work)
3. **Covert channels**: Side-channel attacks between agents (out of scope)

### 2.3 Threat Model

**Attacker**: A malicious or compromised LLM controlling an agent

**Attacker capabilities**:
- Full control over tool invocations within granted tools
- Can craft arbitrary arguments to tools
- Can attempt to load modules dynamically
- Can spawn subagents (if spawn tool granted)
- Knowledge of Inferno internals

**Attacker goals**:
- Access files outside granted paths
- Use tools not granted
- Run shell commands not granted
- Escalate capabilities beyond parent's

**Out of scope**:
- Kernel exploits
- Hardware attacks
- Compromised parent agent (parent is trusted)

---

## 3. Current Implementation Status

### 3.1 Tool Restriction (COMPLETE - Namespace Level)

Child gets its own `tools9p` serving only granted tools:

```limbo
runchild(caps, task)
{
    sys->pctl(Sys->FORKNS|Sys->NEWPGRP, nil);
    sys->unmount(nil, "/tool");
    starttools9p(caps.tools);  // Only granted tools exist
    ...
}
```

**Security property**: Tools not in `caps.tools` do not exist in `/tool`. There is no entry, no Qid, nothing. `ls /tool` shows only granted tools.

### 3.2 Shell Command Restriction (COMPLETE - Namespace Level)

Child's `/dis` is rebuilt with only granted commands:

```limbo
restrictshellcmds(caps.shellcmds)
{
    tmpdir := "/tmp/.restricted_dis";
    mkpath(tmpdir);

    // Bind essentials
    sys->bind("/dis/lib", tmpdir + "/lib", Sys->MREPL);
    sys->bind("/dis/sh.dis", tmpdir + "/sh.dis", Sys->MREPL);
    sys->bind("/dis/veltro", tmpdir + "/veltro", Sys->MREPL);

    // Bind only granted commands
    for(c := caps.shellcmds; c != nil; c = tl c) {
        cmd := hd c;
        sys->bind("/dis/" + cmd + ".dis", tmpdir + "/" + cmd + ".dis", ...);
    }

    // Replace /dis
    sys->bind(tmpdir, "/dis", Sys->MREPL);
}
```

**Security property**: Shell commands not in `caps.shellcmds` do not exist in `/dis`. Running `rm` when only `cat,ls` granted fails with "file not found".

### 3.3 Path Restriction (INCOMPLETE - Policy Level)

Currently implemented as a policy check, not namespace restriction:

```limbo
executetask(task, tools, paths)
{
    (toolname, args) := splitfirst(task);

    // Policy check - NOT namespace enforcement
    if(paths != nil && !pathwithin(args, paths))
        return "ERROR: path not granted";

    tool->exec(args);
}
```

**Problem**: Paths still exist in namespace. Agent can see them. The `exec` tool bypasses this check entirely because shell command arguments can't be reliably parsed.

---

## 4. Approach A: NEWNS + Build Up

### 4.1 Concept

Start with completely empty namespace, add only what's needed:

```limbo
runchild(caps, task)
{
    // 1. Create empty namespace
    sys->pctl(Sys->NEWNS, nil);

    // 2. Bind essential runtime
    bindessentials();

    // 3. Create mount points and bind granted paths
    for(p := caps.paths; p != nil; p = tl p)
        bindfrom("#U", hd p);

    // 4. Start tools9p, etc.
    ...
}
```

### 4.2 Namespace After Construction

```
/
├── dis/
│   ├── lib/           # Essential runtime (bound from #U)
│   ├── sh.dis         # Shell (if exec granted)
│   ├── cat.dis        # Granted shellcmd
│   ├── ls.dis         # Granted shellcmd
│   └── veltro/        # Agent tools
├── dev/
│   ├── cons           # Console
│   └── null           # Null device
├── tool/              # tools9p with granted tools only
├── appl/
│   └── veltro/        # Granted path (bound from #U)
└── tmp/
    └── scratch/       # Agent workspace (if granted)

DOES NOT EXIST (never created):
/usr/
/etc/
/appl/ooda/
/lib/
```

### 4.3 The Bootstrap Problem

After `pctl(NEWNS, nil)`:
- Namespace is completely empty
- No paths exist at all
- Cannot bind to `/dis/lib` because `/dis` doesn't exist
- Cannot create `/dis` because... how?

**The chicken-and-egg**:
1. Need `memfs` or similar to create mount points
2. Cannot load `memfs` because `/dis` doesn't exist
3. Cannot create `/dis` without something to create directories

### 4.4 Potential Solutions to Bootstrap Problem

**Solution A1: Pre-load memfs before NEWNS**

```limbo
// Before NEWNS
memfs := load Memfs "/dis/lib/memfs.dis";

// After NEWNS - memfs module still in memory
sys->pctl(Sys->NEWNS, nil);
memfs->init();  // Create in-memory filesystem
sys->mount(memfs_fd, nil, "/", Sys->MREPL);

// Now we can create directories
mkdir("/dis");
mkdir("/dev");
// ... bind from #U
```

**Solution A2: Use #/ root device**

The `#/` device might provide a minimal root filesystem that can be bound after NEWNS. Need to verify Inferno semantics.

**Solution A3: Keep minimal FDs across NEWNS**

```limbo
// Before NEWNS, open FDs to essential files
dislib_fd := sys->open("/dis/lib", Sys->OREAD);
dev_fd := sys->open("/dev", Sys->OREAD);

// NEWNS with fd preservation
sys->pctl(Sys->NEWNS|Sys->FORKFD, dislib_fd :: dev_fd :: nil);

// Bind using preserved FDs somehow?
// (May not be possible - need to verify)
```

**Solution A4: Kernel modification**

Modify Inferno kernel to support NEWNS with initial bindings. Out of scope for this project.

### 4.5 Security Properties

| Property | Status |
|----------|--------|
| Paths not granted don't exist | ✓ (by construction) |
| No "access denied" on visible paths | ✓ (nothing hidden) |
| Cannot escape via #U | ? (need to verify #U accessibility after NEWNS) |
| Cannot escape via other devices | ? (need to enumerate device access) |
| Capability attenuation guaranteed | ✓ (can only bind from parent's accessible paths) |

### 4.6 Open Questions

1. **Is #U accessible after NEWNS?** If yes, agent could `open("#U/etc/passwd")` directly.
2. **What devices are accessible by name?** `#c`, `#p`, `#U`, etc.
3. **Can memfs be pre-loaded reliably?** Module loading semantics after NEWNS.
4. **What if parent doesn't have memfs?** Capability to create mount points must come from somewhere.

---

## 5. Approach B: FORKNS + Unmount

### 5.1 Concept

Copy parent's namespace, then remove what's not granted:

```limbo
runchild(caps, task)
{
    // 1. Copy parent's namespace
    sys->pctl(Sys->FORKNS|Sys->NEWPGRP, nil);

    // 2. Unmount everything we don't want
    sys->unmount(nil, "/appl");
    sys->unmount(nil, "/usr");
    sys->unmount(nil, "/lib");
    sys->unmount(nil, "/tmp");
    sys->unmount(nil, "/n");
    // ... other known mount points

    // 3. Bind back only granted paths
    for(p := caps.paths; p != nil; p = tl p)
        sys->bind("#U" + hd p, hd p, Sys->MREPL|Sys->MCREATE);

    // 4. Start tools9p, etc.
    ...
}
```

### 5.2 Namespace After Restriction

Same end state as Approach A:

```
/
├── dis/               # Kept (essential)
│   └── ...
├── dev/               # Kept (essential)
├── tool/              # Replaced with restricted tools9p
├── appl/
│   └── veltro/        # Re-bound after unmount
└── tmp/
    └── scratch/       # Re-bound if granted

DOES NOT EXIST (unmounted):
/usr/
/appl/ooda/
/lib/
/n/
```

### 5.3 Implementation Challenges

**Challenge B1: Knowing what to unmount**

Must enumerate all possible mount points. If parent has `/secret/data` mounted and we don't know to unmount it, child retains access.

Possible mitigations:
- Parse `/prog/$pid/ns` to enumerate mounts
- Maintain explicit list of "standard" mount points
- Unmount everything except explicit keep-list

**Challenge B2: Recreating mount points**

After `unmount /appl`, the `/appl` directory may not exist. To bind `/appl/veltro`, need `/appl` as mount point.

```limbo
sys->unmount(nil, "/appl");
// /appl may no longer exist

// This might fail:
sys->bind("#U/appl/veltro", "/appl/veltro", ...);
// Error: /appl does not exist

// Need to create /appl first - but how without memfs?
```

**Challenge B3: Union mount stacks**

Inferno namespaces are stacks. `unmount` removes the top binding. If `/appl` has multiple bindings:

```
/appl <- bind1
/appl <- bind2 (top)
```

One `unmount` removes bind2, leaving bind1. May need multiple unmounts or `unmount` with specific source.

### 5.4 Security Properties

| Property | Status |
|----------|--------|
| Paths not granted don't exist | ~ (only if we unmount everything) |
| No "access denied" on visible paths | ✓ (unmounted paths don't exist) |
| Cannot escape via #U | ? (same concern as Approach A) |
| Cannot escape via other devices | ? (same concern as Approach A) |
| Capability attenuation guaranteed | ~ (only if we don't miss any mounts) |

### 5.5 Open Questions

1. **Can we enumerate all mounts reliably?** `/prog/$pid/ns` parsing.
2. **What happens to mount points after unmount?** Do directories remain?
3. **How to handle union mounts?** Multiple unmounts needed?
4. **Is there a "unmount everything" operation?** Or must we enumerate?

---

## 6. Comparative Analysis

### 6.1 Security Comparison

| Criterion | NEWNS + Build | FORKNS + Unmount |
|-----------|---------------|------------------|
| **Default stance** | Deny all, allow specific | Allow all, deny specific |
| **Unknown paths** | Not accessible (never added) | Accessible (might not unmount) |
| **Completeness** | Complete by construction | Complete only if unmount list complete |
| **Failure mode** | Agent can't run (missing essentials) | Agent has too much access (missed unmount) |
| **#U device access** | Unknown - needs testing | Unknown - needs testing |

### 6.2 Implementation Comparison

| Criterion | NEWNS + Build | FORKNS + Unmount |
|-----------|---------------|------------------|
| **Complexity** | Higher (bootstrap problem) | Lower (no bootstrap) |
| **Dependencies** | May need memfs or similar | Standard syscalls only |
| **Mount point creation** | Must solve (core problem) | Must solve (after unmount) |
| **Testing difficulty** | Easy (check what exists) | Hard (check what doesn't exist) |

### 6.3 Philosophical Comparison

| Criterion | NEWNS + Build | FORKNS + Unmount |
|-----------|---------------|------------------|
| **Security principle** | Allowlist (grant) | Denylist (revoke) |
| **Auditability** | High (see exactly what's granted) | Medium (must verify all unmounts) |
| **Plan 9 idiom** | More idiomatic | Less idiomatic |
| **Maintenance burden** | Lower (explicit grants) | Higher (must track mount points) |

---

## 7. Device Access Concern

Both approaches share a critical concern: **device driver access**.

In Inferno, device drivers are accessed via `#X` syntax:
- `#U` - Host filesystem
- `#c` - Console
- `#p` - Process information
- `#e` - Environment
- `#s` - Server registry

**Question**: After NEWNS or FORKNS+unmount, can a process still access `#U/etc/passwd` directly?

```limbo
// Can agent do this after namespace restriction?
fd := sys->open("#U/etc/passwd", Sys->OREAD);
```

If yes, **both approaches have a bypass vulnerability**.

### 7.1 Potential Mitigations

1. **NODEVS flag**: `pctl(NEWNS|NODEVS, nil)` might restrict device access
2. **Device binding**: Only explicitly bound devices are accessible
3. **Kernel enforcement**: Device access tied to namespace (need to verify)

### 7.2 Required Testing

```limbo
// Test 1: Device access after NEWNS
sys->pctl(Sys->NEWNS, nil);
fd := sys->open("#U/etc/passwd", Sys->OREAD);
// If fd != nil, we have a problem

// Test 2: Device access after FORKNS + unmount
sys->pctl(Sys->FORKNS, nil);
sys->unmount(nil, "/");  // Unmount everything?
fd := sys->open("#U/etc/passwd", Sys->OREAD);
// If fd != nil, we have a problem

// Test 3: NODEVS flag
sys->pctl(Sys->NEWNS|Sys->NODEVS, nil);
fd := sys->open("#c/cons", Sys->OREAD);
// Should this fail?
```

---

## 8. Recommendation Request

We request expert review on:

1. **Feasibility of NEWNS approach**: How to solve the bootstrap problem?
   - Is pre-loading memfs viable?
   - Are there other mechanisms for creating mount points in empty namespace?

2. **Completeness of FORKNS approach**: Can we guarantee all paths are unmounted?
   - Is `/prog/$pid/ns` parsing reliable?
   - Are there hidden mounts we might miss?

3. **Device access semantics**: What devices are accessible after namespace operations?
   - Is `#U` always accessible by name?
   - Does `NODEVS` flag help?
   - How do other Inferno applications handle this?

4. **Recommended approach**: Given our threat model and goals, which approach is preferable?
   - Is the complexity of NEWNS worth the security benefit?
   - Can FORKNS+unmount be made secure enough?
   - Is there a third approach we haven't considered?

---

## 9. Test Cases for Reviewer

### 9.1 Capability Attenuation

```
Parent has: tools=[read,write], paths=[/appl,/tmp]

Test: Child requests tools=[read,write,exec], paths=[/appl]
Expected: Fails - cannot grant exec (parent doesn't have it)

Test: Child requests tools=[read], paths=[/appl,/usr]
Expected: Fails - cannot grant /usr (parent doesn't have it)

Test: Child requests tools=[read], paths=[/appl/veltro]
Expected: Succeeds - /appl/veltro is within parent's /appl
```

### 9.2 Namespace Isolation

```
Child granted: paths=[/appl/veltro]

Test: Child runs "cat /appl/ooda/ooda.b"
Expected: "file not found" (not "access denied")

Test: Child runs "ls /appl"
Expected: Shows only "veltro" (or "directory not found" if /appl not mounted)

Test: Child runs "cat #U/etc/passwd"
Expected: ??? (this is what we need to verify)
```

### 9.3 Shell Command Isolation

```
Child granted: shellcmds=[cat,ls]

Test: Child runs "exec rm /tmp/foo"
Expected: "rm: file not found" (rm doesn't exist in /dis)

Test: Child runs "exec cat /appl/veltro/veltro.b"
Expected: Success (cat exists, path granted)
```

---

## 10. References

1. Plan 9 namespaces: http://doc.cat-v.org/plan_9/4th_edition/papers/names
2. Inferno pctl(2) man page
3. Inferno namespace(4) man page
4. "The Use of Name Spaces in Plan 9" - Pike et al.
5. Veltro implementation: `appl/veltro/` in this repository

---

## Appendix A: Current Code

### A.1 spawn.b runchild() - Current Implementation

```limbo
runchild(pipefd: ref Sys->FD, caps: ref NsConstruct->Capabilities, task: string)
{
    sys->pctl(Sys->FORKNS|Sys->NEWPGRP, nil);

    // Tool restriction (namespace-level)
    sys->unmount(nil, "/tool");
    starttools9p(caps.tools);

    // Shell command restriction (namespace-level)
    if(caps.shellcmds != nil)
        restrictshellcmds(caps.shellcmds);

    // Path restriction - CURRENTLY POLICY-LEVEL, NOT NAMESPACE-LEVEL
    // This is what needs to change

    result := executetask(task, caps.tools, caps.paths);
    writeresult(pipefd, result);
}
```

### A.2 Original NEWNS Implementation (Abandoned)

```limbo
construct(ess: ref Essentials, caps: ref Capabilities): string
{
    // Create new empty namespace
    if(sys->pctl(NEWNS, nil) < 0)
        return sys->sprint("pctl NEWNS failed: %r");

    // Bind essential runtime - THIS FAILED
    // Because after NEWNS, /dis doesn't exist as mount point
    err := bindessentials(ess);
    if(err != nil)
        return err;

    // ... rest of construction
}
```

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **NEWNS** | Create new empty namespace (pctl flag) |
| **FORKNS** | Copy parent's namespace (pctl flag) |
| **NODEVS** | Restrict device access (pctl flag, semantics unclear) |
| **bind** | Make a file/directory appear at a different path |
| **mount** | Attach a file server to a path |
| **unmount** | Remove a binding/mount |
| **#U** | Host filesystem device driver |
| **tools9p** | Synthetic filesystem serving Veltro tools |
| **memfs** | In-memory filesystem for creating mount points |

---

---

## 11. Resolution: Namespace v3 — FORKNS + Bind-Replace

### 11.1 The Third Approach

Neither NEWNS+Build nor FORKNS+Unmount was implemented. Instead, we found a third approach that combines the best properties of both:

**FORKNS + bind-replace (MREPL)**

```limbo
restrictdir(target, allowed)
{
    shadow := create_shadow_dir();
    for(item in allowed)
        bind(target+"/"+item, shadow+"/"+item, MREPL);
    bind(shadow, target, MREPL);  // Replace entire target
}
```

### 11.2 Why This Supersedes Both Approaches

| Criterion | NEWNS+Build (A) | FORKNS+Unmount (B) | FORKNS+Bind-Replace (v3) |
|-----------|-----------------|---------------------|--------------------------|
| Default stance | Deny all | Allow all | Deny all |
| Bootstrap | Chicken-and-egg | No problem | No problem |
| Completeness | By construction | Must enumerate all | By replacement |
| File copying | Required | Not needed | Not needed |
| Cleanup | Required | Not needed | Not needed |
| Failure mode | Can't run | Too much access | Item not visible |

### 11.3 Key Insight

`bind(shadow, target, MREPL)` achieves allowlist semantics without NEWNS:
- **Allowlist**: only items in the shadow are visible (like NEWNS+Build)
- **No bootstrap**: namespace already exists (like FORKNS+Unmount)
- **No enumeration**: don't need to know what to remove
- **Idempotent**: can be applied multiple times to narrow further

### 11.4 Device Access Resolution

The #U device access concern (Section 7) is resolved by:
1. `restrictdir("/", safe)` — replaces root union, hiding #U-exposed project files
2. `restrictdir("/n", allowed)` — hides `/n/local` (host filesystem mount)
3. `pctl(NODEVS)` — blocks `#X` device naming (child only)
4. Parent doesn't need NODEVS because bind-replace hides unrestricted content

### 11.5 Implementation Details

**Core module**: `nsconstruct.b` (~455 lines, was ~863 in v2)

Three entry points apply restriction:
- **tools9p serveloop**: FORKNS after mount() completes, via non-blocking alt on buffered channel
- **repl init**: FORKNS after mount checks, before LLM session
- **spawn child**: FORKNS in runchild(), with full NEWPGRP/NEWENV/NEWFD/NODEVS sequence

**Restriction policy** (`restrictns()`):
1. `/dis` → `lib/`, `veltro/` (+ shell commands if granted)
2. `/dis/veltro/tools` → only granted tool .dis files
3. `/dev` → `cons`, `null`
4. `/n` → `llm/` (if mounted), `speech/` (if mounted), `mcp/` (if mc9p)
5. `/n/local` → only granted subpaths (recursive drill-down)
6. `/lib` → `veltro/`
7. `/tmp` → `veltro/`
8. `/` → 13 safe Inferno system directories (hides .env, .git, CLAUDE.md, source tree)

**Implementation challenges solved**:
- **Root restriction**: `dirread()` returns entries from ALL union members. Individual bind-overs don't hide entries. Solution: `restrictdir("/", safe)` replaces the entire root union.
- **9P self-mount deadlock**: `stat("/tool")` in tools9p serveloop deadlocks because `/tool` is the serveloop's own 9P mount. Solution: skip stat for `target == "/"`, create mount points unconditionally.
- **Double-slash path**: When `target == "/"`, `target + "/" + item` produces `//dev`. Solution: special-case for root target.
- **Speech preservation**: `/n/speech` must survive `/n` restriction for the `say` tool. Solution: auto-detect via stat and include in allowlist.

**Subagent architecture**: Children use pre-loaded tool modules directly (not tools9p). The `spawn` tool calls `preloadmodules()` before `spawn runchild()`, loading Tool modules and their dependencies while `/dis` is unrestricted. The child's `subagent->runloop()` calls `mod->exec(args)` on module references already in memory.

**Verification**: `verifyns()` performs both positive assertions (expected paths accessible) and negative assertions (`stat()` on `/.env`, `/.git`, `/CLAUDE.md`, `/n/local` must fail).

See `appl/veltro/SECURITY.md` for the full security model documentation.

*v3 implemented: 2026-02-13*

---

*Document prepared for security review. Last updated: 2026-02-13*
