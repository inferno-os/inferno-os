# Veltro Security Model (v3)

## Overview

Veltro uses Inferno OS namespace isolation to create secure environments for AI agents. The core primitive is `restrictdir(target, allowed, writable)`: create a shadow directory containing only allowed items, then bind-replace the target. Anything not in the allowlist becomes invisible. The `writable` flag adds `MCREATE` to the final bind, needed for `/tmp` so agents can create files there.

### Terminology

This document distinguishes:

- **Harness** — the namespace-restriction machinery itself: `nsconstruct`,
  `tools9p`, `lucibridge`, and the `veltro`/`repl`/`spawn` entry points that
  call `restrictns(caps)`. The harness defines what an agent *can* do.
- **Agent** — a running process executing the harness loop with a model and a
  capability set. Each `repl`, `veltro`, `lucibridge`, or `spawn`'d child is a
  separate agent with its own restricted namespace.
- **Subagent** — an agent created by another agent via the `spawn` tool.
  Subagents inherit an already-restricted namespace and can only narrow it
  further (capability attenuation).

The security model applies to **agents**: the harness restricts what each
running instance sees. The harness itself is trusted code.

Three harness entry points apply namespace restriction:

| Entry Point | Where | When |
|-------------|-------|------|
| `tools9p` serveloop | `appl/veltro/tools9p.b` | After mount(), before first tool exec |
| `repl` init | `appl/veltro/repl.b` | After mount checks, before LLM session |
| `spawn` child | `appl/veltro/tools/spawn.b` | In runchild(), before subagent->runloop() |

All three call `nsconstruct->restrictns(caps)` after `pctl(FORKNS)`.

## How It Works

### Core Primitive: `restrictdir(target, allowed, writable)`

```
1. Create unique shadow dir: /tmp/veltro/.ns/shadow/{pid}-{seq}/
2. For each item in allowed:
   - Create mount point in shadow (dir or file matching source type)
   - bind(target/item, shadow/item, MREPL)
3. flags = MREPL | (writable ? MCREATE : 0)
   bind(shadow, target, flags)  -- replace entire target
4. Result: target shows only allowed items; everything else is gone
```

`writable=1` adds `MCREATE` to the final bind so file creation is permitted at the
mount point. Required for `/tmp`; all other directories use `writable=0`.

Special handling for `target == "/"`:
- Skips `stat()` on each item to avoid deadlock on 9P self-mounts (e.g., `/tool`)
- Creates directory mount points unconditionally
- Bind failures are non-fatal (item may not exist in current namespace)

### Two-Level Restriction

```
tools9p/repl:   FORKNS + restrictns()   -- restrict agent's namespace
subagent spawn: FORKNS + restrictns()   -- inherit + further restrict
```

Both levels use the same `restrictdir()` primitive. Capability attenuation is natural: children fork an already-restricted namespace and can only narrow further.

## Namespace Restriction Policy

`restrictns(caps)` applies these restrictions in order:

| Step | Target | Allowed | writable | Purpose |
|------|--------|---------|----------|---------|
| 1 | `/dis` | `lib/`, `veltro/` (+ `sh.dis` if exec or shellcmds granted, + named cmds if shellcmds granted) | 0 | Runtime + agent modules only |
| 2 | `/dis/veltro/tools` | Only granted tool .dis files (if caps.tools is set) | 0 | Per-agent tool allowlist |
| 3 | `/dev` | `cons`, `null` | 0 | Minimum devices |
| 4 | `/n` | `llm/` (if mounted), `mcp/` (if mc9p), `speech/` (if speech9p), `git/` (if git9p), `local/` (only if caps.paths grants subpaths) | 0 | Network/service mounts |
| 5 | `/n/local` | Only granted subpaths (recursive restrictdir) | 0 | Host filesystem drill-down |
| 6 | `/lib` | `veltro/` | 0 | Agent config, tools, reminders |
| 7 | `/tmp` | `veltro/` | **1** | Shadow dirs + scratch space — writable so agents can create files |
| 8 | `/` | `dev`, `dis`, `env`, `fd`, `lib`, `n`, `net`, `net.alt`, `nvfs`, `prog`, `tmp`, `tool` (+ `chan` only if `caps.xenith`) | 0 | Hide project files (.env, .git, CLAUDE.md, etc.) |

**Order matters**: Steps 1-7 create shadow dirs under `/tmp/veltro/.ns/shadow/`. Step 7 restricts `/tmp` but preserves the `veltro/` subtree. Step 8 restricts `/` last, after all subdirectory restrictions are in place.

**`/chan` access control**: The Xenith 9P filesystem at `/chan` exposes ALL window contents. Without the `xenith` capability flag, `/chan` is excluded from the root allowlist — the agent cannot see or read any Xenith windows. When `caps.xenith` is set (e.g., tools9p detects the xenith tool was granted), `/chan` is included. The REPL opens its own window FDs before restriction, so it works without `/chan` in the namespace.

## Namespace After Restriction

### Parent agent (started via `tools9p` / `repl` harness entry points)

```
/
+-- chan/          Xenith 9P (ONLY if xenith tool granted)
+-- dev/
|   +-- cons      console I/O
|   +-- null      null device
+-- dis/
|   +-- lib/      Limbo runtime libraries
|   +-- veltro/   agent modules + tools
+-- env/          environment variables
+-- fd/           file descriptor device
+-- lib/
|   +-- veltro/   agents/, reminders/, tools/, system.txt
+-- n/
|   +-- llm/      LLM access (if mounted)
|   +-- speech/   speech synthesis/recognition (if mounted)
+-- net/          TCP/IP networking
+-- nvfs/         name-value filesystem
+-- prog/         process information
+-- tmp/
|   +-- veltro/
|       +-- scratch/     agent workspace
|       +-- .ns/         shadow dirs + audit logs
+-- tool/         tools9p mount (9P filesystem)

NOT VISIBLE after restriction:
/.env, /.git, /CLAUDE.md        project secrets/config
/appl, /emu, /module, /mkfiles  source tree
/n/local                        host macOS filesystem
/chan                            Xenith windows (unless xenith tool granted)
/fonts, /icons, /man            non-essential data
/dis/*.dis                      top-level commands
```

### Child Subagent (spawn)

Inherits parent's already-restricted namespace, then further restricts:
- `/dis/veltro/tools/` narrowed to only granted tool .dis files
- Everything else inherited from parent (already restricted)

## Entry Point Details

### tools9p Serveloop Restriction

The tools9p server must restrict its own thread's namespace, but faces a chicken-and-egg problem: the serveloop must be running before `mount()` can succeed (mount sends 9P messages), but FORKNS must happen after mount so `/tool` is captured.

**Solution**: Buffered channel synchronization with non-blocking alt.

```
init():
  1. Create buffered channel: mounted := chan[1] of int
  2. spawn serveloop(... mounted)
  3. mount(fds[1], "/tool", MREPL)    -- 9P traffic flows to serveloop
  4. mounted <-= 1                     -- signal serveloop

serveloop():
  On each 9P message, non-blocking check:
    alt {
    <-mounted => applynsrestriction(); restricted = 1;
    * => ;  // mount not ready yet
    }
```

After restriction, all async tool execution threads (via `spawn asyncexec()`) inherit the restricted namespace.

### repl Restriction

The REPL applies restriction after verifying `/tool` and `/n/llm` are mounted, but before creating the LLM session:

```
1. Load NsConstruct module (while /dis unrestricted)
2. Read /tool/tools -- get live tool list before restriction
3. pctl(FORKNS)
4. restrictns(caps)   -- caps.tools = live tool list; caps.paths = -p flag paths
5. Create LLM session -- /n/llm still accessible
6. Enter repl loop
```

### spawn Child Restriction

The child process applies the full isolation sequence:

```
1. pctl(NEWPGRP)         -- Fresh process group (empty srv registry)
2. pctl(FORKNS)          -- Fork parent's restricted namespace
3. pctl(NEWENV)          -- Empty environment (NOT FORKENV!)
4. Open LLM FDs          -- While /n/llm still accessible from parent
5. restrictns(caps)      -- Further bind-replace restrictions
6. verifysafefds()       -- Redirect FDs 0-2 to /dev/null if nil
7. pctl(NEWFD, keepfds)  -- Prune all other FDs
8. pctl(NODEVS)          -- Block #U/#p/#c device naming
9. subagent->runloop()   -- Execute task with pre-loaded tool modules
```

## Subagent Architecture

Subagents do NOT use tools9p. They use pre-loaded tool modules directly.

```
Parent (spawn.b):
  1. preloadmodules(tools)    -- load Tool modules while /dis accessible
  2. preload subagent.b       -- load SubAgent module
  3. spawn runchild()         -- child inherits loaded modules in memory

Child (runchild):
  1. Apply namespace restrictions (steps 1-8 above)
  2. Build tool list from preloadedtools (already in memory)
  3. subagent->runloop(task, toolmods, toolnames, prompt, llmfd, 50)
```

The subagent's system prompt comes from `/lib/veltro/agents/{type}.txt`, loaded before namespace restriction. Tool invocations in the runloop call `mod->exec(args)` directly on the pre-loaded module references.

## Security Properties

| Property | Mechanism |
|----------|-----------|
| No host filesystem access | `/n/local` hidden by `/n` restriction; `#U` blocked by NODEVS (child) |
| No project file exposure | Root restriction hides `.env`, `.git`, `CLAUDE.md`, source tree |
| No env secrets | NEWENV creates empty environment (child) |
| No FD leaks | NEWFD with explicit keep-list (child) |
| Safe FD 0-2 | `verifysafefds()` redirects nil FDs to `/dev/null` |
| Empty srv registry | NEWPGRP first (child) |
| Truthful namespace | bind-replace shows only allowed items; no "access denied" on visible paths |
| Capability attenuation | Child forks restricted parent, can only narrow |
| No cleanup needed | bind-replace is namespace-only, no physical directories to manage |
| Auditable | `verifyns()` checks for dangerous paths; `emitauditlog()` records operations |
| No cross-window access | `/chan` hidden unless `caps.xenith` is set; REPL opens FDs before restriction |
| exec grants sh.dis only | `sh.dis` bound when `exec` is in caps.tools; named commands require `shellcmds` |
| Shell access controlled | `sh.dis` + named command `.dis` files only bound if `shellcmds` is non-nil |
| /tmp writable | `restrictdir("/tmp", ..., 1)` — MCREATE applied only to /tmp, not /dis/lib/dev |
| Host path control | `/n/local` hidden unless `caps.paths` grants specific subpaths (`-p` flag) |
| Speech preserved | `/n/speech` auto-detected and included in `/n` allowlist |
| 9P self-mount safe | Root restriction skips `stat()` to avoid deadlock on `/tool` |

## Shell and Exec Access

The `exec` tool and `shellcmds` field both affect what appears in `/dis`:

```
# exec in caps.tools (no shellcmds) -- sh.dis added to /dis allowlist
# Agent can run: exec cat /dev/sysname (using full /dis/cat.dis path)
caps := ref Capabilities("exec" :: ..., nil, nil, ...);

# shellcmds -- sh.dis + named .dis files added to /dis allowlist
# Agent can run commands by name: exec cat /dev/sysname
caps := ref Capabilities(..., nil, "cat" :: "ls" :: nil, ...);
```

`exec` grants `sh.dis` only (the shell interpreter). Named top-level commands
like `cat.dis`, `ls.dis`, `date.dis` require explicit `shellcmds` entries.
This is a two-level gate: exec access ≠ arbitrary command access.

## Invocation

### Starting the Agent

Veltro requires tools9p to be started first. The caller chooses which tools to grant, and optionally which host filesystem paths to expose:

```sh
# Inside Inferno (emu):

# Start tool server with specific tools, then launch interactive REPL
/dis/veltro/tools9p read list find search spawn edit write xenith say; /dis/veltro/repl

# Single-shot task with minimal tools
/dis/veltro/tools9p read list; /dis/veltro/veltro 'list the files in /appl/cmd'

# Full tool set (trusted use)
/dis/veltro/tools9p read list find search write edit exec spawn xenith say hear ask diff json http git memory todo websearch grep mail; /dis/veltro/repl -v

# Expose a host filesystem path to the agent (-p flag, comma-separated)
/dis/veltro/tools9p read list find grep; /dis/veltro/repl -p /n/local/Users/pdfinn/projects

# Multiple paths
/dis/veltro/tools9p read list write edit; /dis/veltro/veltro -p /n/local/Users/pdfinn/projects,/n/local/Users/pdfinn/docs 'review the docs'
```

**This separation is intentional security architecture**: capability granting flows from caller to callee, never the reverse. The `-p` flag controls host filesystem access; without it, `/n/local` is completely hidden.

### Spawning Subagents

From within an agent session:

```
spawn tools=read,list -- list the contents of /n and /tmp
spawn tools=read,list,find agenttype=explore -- find all .b files under /appl
spawn tools=read agenttype=plan model=sonnet -- plan a refactor of repl.b
spawn tools=read,write,edit shellcmds=cat,ls -- edit /tmp/veltro/scratch/notes.txt
```

Options:
- `tools=<csv>` -- tools to grant (required)
- `paths=<csv>` -- host filesystem paths to expose (optional)
- `shellcmds=<csv>` -- shell commands to allow (grants sh.dis + named cmds)
- `agenttype=<type>` -- agent prompt: default, explore, plan, task
- `model=<name>` -- LLM model (default: haiku)
- `temperature=<float>` -- 0.0-2.0 (default: 0.7)
- `thinking=<val>` -- off, max, or token budget 0-30000
- `system=<prompt>` -- explicit system prompt (overrides agenttype)

### Speech

If speech9p is mounted at `/n/speech`:
- `say <text>` -- text-to-speech output
- `hear` -- speech-to-text input (5-second recording)
- `Voice` button in Xenith REPL for voice input

## Verification

`verifyns(expected)` performs post-restriction auditing:

1. Reads `/prog/$pid/ns` for current namespace state
2. Checks for known dangerous paths in mount table (`/n/local`, `#U` bindings)
3. Negative assertions: `stat()` on `/.env`, `/.git`, `/CLAUDE.md`, `/n/local` -- must fail
4. Positive assertions: `stat()` on expected paths -- must succeed
5. Returns nil on success, violation description on failure

## Design Decisions

### Why bind-replace (v3) instead of NEWNS + sandbox (v2)?

| Criterion | v2 (NEWNS + sandbox) | v3 (FORKNS + bind-replace) |
|-----------|---------------------|---------------------------|
| File copying | Required (NEWNS loses binds) | None |
| Cleanup | Required (rmrf sandbox dir) | None (namespace-only) |
| Bootstrap | Chicken-and-egg problem | No problem (fork existing) |
| Code size | ~860 lines | ~455 lines |
| Security model | Allowlist (by construction) | Allowlist (by replacement) |
| Race conditions | Create-fails-if-exists | PID-scoped shadow dirs |

### Why restrict `/` (root)?

When running `emu -r.`, the host project directory is bound onto `/` with MAFTER. This exposes `.env`, `.git`, `CLAUDE.md`, and the entire source tree. Individual bind-overs on entries don't affect `dirread()` -- Inferno's union mount returns entries from ALL union members. The only way to hide entries is to replace the entire root union with `restrictdir("/", safe)`.

### Why skip stat() for root entries?

`stat("/tool")` in the tools9p serveloop deadlocks: `/tool` is the serveloop's own 9P mount, and stat sends a 9P Tstat message that the serveloop can't process because it's blocked on stat. Solution: for `target == "/"`, create directory mount points unconditionally and let bind failures be non-fatal.

### Shadow Directory Management

Shadow directories are created under `/tmp/veltro/.ns/shadow/` with `{pid}-{seq}` names. PID prefix avoids collisions between parent and child. After `/tmp` is restricted to only `veltro/`, the shadow dirs remain accessible.

## Files

| File | Purpose |
|------|---------|
| `appl/veltro/nsconstruct.m` | Module interface: restrictdir, restrictns, verifyns, emitauditlog |
| `appl/veltro/nsconstruct.b` | Core implementation (~455 lines) |
| `appl/veltro/tools9p.b` | Tool filesystem server with serveloop namespace restriction |
| `appl/veltro/repl.b` | Interactive REPL with namespace restriction at init |
| `appl/veltro/tools/spawn.b` | Secure subagent spawn with FORKNS + restrictns |
| `appl/veltro/subagent.b` | Subagent runloop (runs in restricted namespace) |
| `lib/veltro/agents/*.txt` | Agent type prompts (default, explore, plan, task) |
| `lib/veltro/system.txt` | System prompt (output format specification) |
| `lib/veltro/reminders/security.txt` | Security reminders injected into prompts |
| `lib/veltro/tools/spawn.txt` | Spawn tool documentation |

## Testing

Security tests are in `tests/veltro_security_test.b`:

```sh
export ROOT=$PWD && export PATH=$PWD/MacOSX/arm64/bin:$PATH
cd tests && mk install
./emu/MacOSX/o.emu -r. /tests/veltro_security_test.dis -v
```

Tests cover:
- `restrictdir()` allowlist (only allowed items visible)
- `restrictdir()` exclusion (non-allowed items invisible)
- `restrictdir()` idempotent (multiple calls safe)
- `restrictns()` full policy (/dis, /dev, /n, /lib, /tmp, /)
- `restrictns()` shell access via shellcmds
- `restrictns()` concurrent (race safety)
- `verifyns()` violation detection
- Audit logging
- Missing items handled gracefully
- `/tmp` writable after restriction (MCREATE on shadow bind)
- `exec` in tools grants `sh.dis` without `shellcmds`
- `caps.paths` exposes granted `/n/local/` subtree

Concurrency tests in `tests/veltro_concurrent_test.b`:
- Concurrent init
- Concurrent restrictdir
- Concurrent restrictns

## Future Investigation: nsaudit

### Not verification — syntactic analysis

The existing `formal-verification/` tree proves properties of the kernel's
namespace primitives: 3.17 billion TLA+ states, SPIN model checks, CBMC
harnesses over `pgrpcpy` and friends. Those proofs are about the mechanism.

`nsaudit` is about the *configuration* that feeds the mechanism. It parses a
capability configuration, looks up each tool in a per-tool authority
manifest, and applies pattern-match rules over the resulting authority set.
No symbolic execution, no theorem, no proof. This is syntactic analysis —
closer to a linter or a type checker than to TLA+. The two efforts are
complementary: `formal-verification/` proves the kernel does what it's
told; `nsaudit` checks that what you're telling it is what you meant.

### The question it answers

A single question, asked daily and asked under different urgencies:

> **"What does this namespace configuration actually allow the agent to do?"**

- *Daily debugging (high volume, low stakes)*: "My agent can't see
  `/n/local/foo/bar` and I don't know why. What did I miss?" — `nsaudit
  -reach /n/local/foo/bar` answers it.
- *Shipping defaults (low volume, very high stakes)*: "The config we ship to
  every InferNode install — does it grant an agent escape valve we didn't
  intend?" — `nsaudit` run on a committed fixture, diffed against a
  committed snapshot, gated in CI.
- *Tool development (per tool)*: "The new tool I'm writing — what authority
  does it actually add to an agent's caps?" — tool author runs `nsaudit`
  against a test fixture that includes their tool and reviews the report.
- *Security review (per release, per incident)*: "The Meta Agent has
  capabilities we've never formally scoped. What can it reach and cause?" —
  `nsaudit` run against the meta-agent fixture, violations section reviewed
  by hand.

Same tool, same engine. Different modes emphasize different parts of the
same underlying analysis.

**`nsaudit` is advisory, not enforcing.** The namespace is still what
enforces. `restrictns()`, `FORKNS`, `NODEVS`, cowfs overlays, and
`wallet9p`'s per-transaction gating are the runtime gate; `nsaudit` is the
pre-flight review. If you ship a misconfigured caps, `nsaudit`'s warning
does not help you at runtime — only the correctness of the caps themselves
does. The value `nsaudit` adds is making misconfiguration visible before
it ships.

### Data model

All inputs and outputs are files. No serialization format is invented; no
in-tree JSON; everything is either a directory of scalar files (like
`tools9p` already uses) or an ndb(6) attribute file (like factotum and cs
already use). Inferno has `attrdb(2)` in `module/attrdb.m` and the ndb
parser in `appl/cmd/ndb/`.

**Caps input — a directory of scalar files** (the format `tools9p` already
exposes at `/tool/`):

    /tool/tools       one tool name per line
    /tool/paths       one path grant per line
    /tool/meta/role   "toplevel" or "child"
    /tool/meta/xenith "1" or "0"
    /tool/meta/actid  integer or "-1"
    /tool/meta/nodevs "set" or "unset"

Live audit: `nsaudit /tool`. Hypothetical analysis: construct a mock
directory of the same shape. Fixtures for CI are directories of the same
shape.

A small addition to `tools9p` is required: expose `role`, `xenith`, `actid`,
`nodevs` as scalar files under `/tool/meta/`. Without this, `nsaudit` only
sees `tools` and `paths`.

**Tool authority manifest — ndb files at `lib/veltro/nsaudit/authorities/<tool>`:**

    ; cat lib/veltro/nsaudit/authorities/exec
    description  Execute a shell command via sh.dis
    authorities  spawns_proc execs_code reads_fs writes_fs dials_net
    irreversible spawns_proc writes_fs dials_net
    notes        Force multiplier. Grants anything the spawned shell can
                 reach within the agent's namespace. Scope limited by
                 caps.shellcmds if set, otherwise unrestricted.

One file per tool. Adding a tool means adding a file. Reviewed at every
new tool.

**Rules — ndb files at `lib/veltro/nsaudit/rules/<name>`:**

    ; cat lib/veltro/nsaudit/rules/device-gate-bypass
    name      DEVICE_GATE_BYPASS
    severity  high
    condition role=toplevel nodevs=unset
    message   top-level caps grants kernel device attach without NODEVS.
              Any sys->bind on an #x device will succeed, reaching
              #sfactotum, #U (host fs), or other kernel services
              regardless of path-based restriction.
    fix       add sys->pctl(Sys->NODEVS, nil) after the FORKNS site

One file per rule. Adding a rule means adding a file (and a test).

**Suppressions — ndb files at `lib/veltro/nsaudit/suppressions/<fixture>.<rule>`
with expiry:**

    ; cat lib/veltro/nsaudit/suppressions/shipping-default-full.exec-force-multiplier
    rule     EXEC_FORCE_MULTIPLIER
    scope    fixture=shipping-default-full
    reason   Interactive REPL exposes exec so power users can run
             commands. Scoped by caps.shellcmds and user consent at
             first launch.
    reviewed 2026-04-11
    by       pdfinn
    expires  2026-10-11

Expired suppressions fail CI. Every rule suppression is a named, dated
file — no hidden exceptions.

### Authority axes (closed set)

The soundness of syntactic analysis depends on the axis set being closed
and enumerable. Adding a new axis is a deliberate act, not a derivation:

| Category | Axis | Source |
|---|---|---|
| Filesystem | `reads_fs` | tool manifest, `caps.paths` |
| Filesystem | `writes_fs` | tool manifest, `caps.paths` |
| Filesystem | `writes_fs_durable` | `writes_fs` ∧ not `/tmp/veltro` ∧ `actid < 0` |
| Network | `dials_net` | tool manifest, `caps.mcproviders` |
| Network | `listens_net` | tool manifest |
| Process | `spawns_proc` | tool manifest (e.g. exec, spawn, launch) |
| Process | `signals_proc` | tool manifest |
| Process | `execs_code` | tool manifest |
| Kernel | `attaches_device` | `role=toplevel` ∧ `nodevs=unset` |
| Secrets | `reads_secrets_factotum` | `/mnt/factotum` in reads_fs |
| Secrets | `reads_env` | `NEWENV` unset |
| Economic | `spends` | tool manifest (wallet, pay) |
| Comms | `sends_llm` | tool manifest, `caps.llmconfig` |
| Comms | `sends_ui` | `caps.xenith` ∨ `/n/ui` in writes_fs |
| Comms | `receives_input` | `/dev/cons` in reads_fs |
| Windows | `reads_windows` | `caps.xenith` |
| Windows | `modifies_windows` | `caps.xenith` |
| Memory | `persists_memory` | `caps.memory` |

### Initial rule set

Each rule is a file at `lib/veltro/nsaudit/rules/`, each with a test
under `tests/nsaudit-rules/`. New rules land as (file, test) pairs.

| Rule | Condition | Severity |
|---|---|---|
| `DEVICE_GATE_BYPASS` | `role=toplevel` ∧ `nodevs=unset` | high |
| `EXFIL_RISK_EGRESS` | `reads_fs ∩ (dials_net ∨ sends_llm ∨ spawns_proc)` | high |
| `EXEC_FORCE_MULTIPLIER` | `exec` in tools | info |
| `UNCONSTRAINED_SHELL` | `exec` in tools ∧ `shellcmds` empty | high |
| `SPAWN_INHERITANCE` | `spawn` in tools ∧ `writes_fs_durable` | medium |
| `DURABLE_HOST_MUTATION` | `writes_fs_durable` non-empty | medium |
| `UNBOUNDED_SPEND` | `spends` without per-call gating metadata | high |
| `LLM_AS_EGRESS_FOR_SECRETS` | `sends_llm` ∧ reads_fs contains secrets path | high |
| `NET_EGRESS_IMPLICIT` | `dials_net` without matching `mcproviders` entry | medium |
| `SUBAGENT_MISSING_NODEVS` | `role=child` ∧ `nodevs=unset` | high |

`SUBAGENT_MISSING_NODEVS` is worth highlighting: it turns the
`spawn.b:576` `pctl(NODEVS)` call from an implementation detail into a
checked property. If someone edits `spawn.b` and removes the NODEVS call,
the subagent fixture snapshot regenerates without `nodevs=set`, the rule
fires, CI fails.

### CI gate

The gate is not runtime enforcement. It is a build-time check that
shipping configurations match committed expectations.

**Fixtures at `tests/nsaudit-fixtures/<name>/`:** directories of the same
shape as a live `/tool`, one per shipping configuration.

- `shipping-default-full` — full GUI (`lib/lucifer/boot.sh` line 48)
- `shipping-default-headless` — REPL without GUI
- `shipping-default-subagent` — spawned child config (must have
  `nodevs=set`)
- `meta-agent` — the Meta Agent / Chief of Staff config used by
  `lucibridge` at activity 0 (first high-value target)
- `lucifer-gui` — lucifer's own context-zone namespace (second
  high-value target)
- `shipping-default-minimal` — smallest viable agent

**Snapshots at `tests/nsaudit-fixtures/<name>/expected.ns`:** committed
ndb file containing the authority inventory, violations list, and
suppression references. The source of truth for "what this config grants."

**The gate itself:** a `mk nsaudit-check` target in `tests/mkfile` that
runs `nsaudit` against every fixture and diffs the output against the
snapshot. Exit nonzero on any difference. Wire into
`.github/workflows/` alongside the existing security checks.

A companion script, `tests/nsaudit-fixtures/verify-matches-boot.sh`,
diffs fixture contents against the tool lists in `lib/lucifer/boot.sh`,
`dis/lucifer-start.sh`, `run-lucia.sh`, and friends — so the fixture
cannot silently drift from the real shipping commands.

Updating a fixture or snapshot requires a deliberate edit in the PR,
visible to reviewers. Adding a suppression requires a named, dated file
with an expiry. Both force conscious decisions about what authorities
ship by default.

### What nsaudit cannot answer

Stated plainly, because a tool that over-claims is worse than no tool:

- **Prompt injection propagation.** If the agent reads attacker-controlled
  data and the LLM chooses to act on it, effective authority becomes
  whatever the model decides. Not statically decidable.
- **Semantic reversibility.** "Agent overwrote `notes.txt`" is
  reversible with backups, not without. Context-dependent.
- **Manifest truthfulness.** A lying manifest entry is undetectable to
  `nsaudit`. The runtime ground-truth check (below) is the safety net.
- **Tool-internal composition.** A tool that invokes sub-tools not named
  in its manifest entry is as good as its manifest, no better.

A caps that passes `nsaudit` is *not* "safe." It is "free of the
authority compositions `nsaudit` knows to check for." That ceiling is the
right one to advertise.

### Runtime ground-truth check

The one place runtime code is needed is the cross-check: does `nsaudit`'s
static model of `reads_fs` agree with what `restrictns()` actually
produces at runtime?

A test (`tests/nsaudit_groundtruth_test.b`) forks, applies real
`restrictns(caps)` for each fixture, walks the resulting namespace with a
bounded BFS, and asserts the walked set equals the `reads_fs` set the
linter computed for the same caps. Any disagreement means either the
linter's model or the implementation has drifted — both are real bugs.

This is where `nswalk` lives: not as a user-facing tool, but as a
subroutine of the ground-truth check. Once it exists as a subroutine,
exposing it as a user tool is cheap.

### NODEVS short-term fix, independent of nsaudit

`pctl(NODEVS)` is applied only in the spawned-child path
(`spawn.b:576`). Top-level agents (`veltro.b:168`, `repl.b:169`,
`tools9p.b:644`) call `pctl(FORKNS)` and `restrictns()` but leave
`pgrp->nodevs == 0`. The kernel device gate is at
`emu/port/chan.c:1041-1051`; with `nodevs` unset, `sys->bind("#sfactotum",
"/tmp/veltro/x", MREPL)` succeeds and reaches factotum regardless of
path-based restriction.

Today this is latent — top-level agents do not invoke `bind` on `#x`
paths from model-driven code. It becomes exploitable the moment any tool
or exec invocation does.

Fix: add `sys->pctl(Sys->NODEVS, nil)` to the three top-level FORKNS
sites. The kernel gate is strictly stronger than the path gate for
device-attach, and none of the top-level agents has a documented need for
`#x` devices outside the `nodevs` allowlist (`|esDa`). Once fixed,
`SUBAGENT_MISSING_NODEVS` plus an analogous `TOPLEVEL_MISSING_NODEVS`
rule keep it fixed.

### Sequencing

1. **CLI skeleton** (`appl/cmd/nsaudit.b`): ndb parsing via
   `Attrdb`, three modes — full report, `-reach PATH`, `-d before after`.
   ~300 lines. Runs inside emu, no namespace manipulation.
2. **Per-tool manifest** for existing tools in `appl/veltro/tools/`.
   One file per tool, ndb format. Each entry is a small act of honest
   assessment — read the tool's source, decide what authorities it grants.
3. **Initial rule set** — the ten rules above, one file each,
   test-per-rule.
4. **Initial fixtures** — `meta-agent` first (the user's stated priority),
   then `lucifer-gui`, then the three shipping defaults, then `minimal`.
5. **CI gate** — `mk nsaudit-check` + snapshot diff + boot-script drift
   detection.
6. **Runtime ground-truth check** (`tests/nsaudit_groundtruth_test.b`)
   using a bounded `nswalk` subroutine. Catches manifest/implementation
   drift.
7. **`tools9p` metadata exposure** — scalar files under `/tool/meta/`.
8. **lucictx integration** — new collapsible Authority section;
   re-run `nsaudit` on every `/tool/ctl` write; inline `-reach PATH` on
   hover in the file browser.
9. **Staging/preview** — right-click "What would change?" in lucictx
   runs `nsaudit -d` between current `/tool` and a staged mock.

Steps 1–5 are the shipping-gate MVP. That is what protects the defaults.
Steps 6–9 add the debug UX and the live GUI. Every step is additive; the
earlier steps keep working as the later ones land.

### Prior art, or lack thereof

No tool exists in the Plan 9 / Inferno / 9front ecosystem for namespace
safety analysis (verified 2026-04). The closest things are `ns(1)`
(inspection only) and ANTS's per-process `/srv` (mitigation, not
analysis). No tool exists in the broader capability-OS literature for
authority inventory over a running agent's caps either —
seL4/EROS/KeyKOS verify confinement at the kernel level but do not
produce human-readable authority reports for application-level capability
sets. `nsaudit` fills unclaimed ground.

### Current state

- `appl/cmd/nsaudit.b` — CLI skeleton (in progress).
- `lib/veltro/nsaudit/authorities/` — one entry (in progress).
- `lib/veltro/nsaudit/rules/` — one entry (in progress).
- `tests/nsaudit-fixtures/minimal/` — first fixture (in progress).
- No `tools9p` metadata exposure yet.
- No runtime ground-truth check yet.
- No lucictx integration yet.
- No `meta-agent` or `lucifer-gui` fixture yet — those are the first real
  targets after the CLI and one fixture work end-to-end.
