# Veltro Security Model (v3)

## Overview

Veltro uses Inferno OS namespace isolation to create secure environments for AI agents. The core primitive is `restrictdir(target, allowed, writable)`: create a shadow directory containing only allowed items, then bind-replace the target. Anything not in the allowlist becomes invisible. The `writable` flag adds `MCREATE` to the final bind, needed for `/tmp` so agents can create files there.

Three entry points apply namespace restriction:

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

### Parent Agent (tools9p / repl)

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
