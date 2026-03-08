# Veltro Architecture Review: Tool/App Unification

## Current State

Three categories of AI-accessible capabilities exist:

| Category | Examples | Interface | Discovery | Security |
|----------|----------|-----------|-----------|----------|
| **Headless tools** | exec, grep, read, write, git | `tool.m` (init/name/doc/exec) | `/tool/tools` listing | Namespace restriction on `/dis/veltro/tools/` |
| **App-backed tools** | lucishell, luciedit, charon, fractal | Tool wraps 9P filesystem at `/tmp/veltro/{app}/` | Same `/tool/tools` listing | Tool registration + app must be running |
| **Lucifer zone apps** | luciconv, lucipres, lucictx | 9P at `/n/ui/` | Implicit (always present) | Part of Lucifer lifecycle |

## What Works Well

1. **`tool.m` is clean** -- four functions (`init`, `name`, `doc`, `exec`) is a good minimal interface. The AI gets a uniform call pattern regardless of what's behind it.

2. **Namespace = capability** is elegant -- `nsconstruct.b`'s shadow-directory approach and the `Capabilities` ADT are architecturally sound. Removing a tool from `/dis/veltro/tools/` makes it invisible to the agent.

3. **9P as the IPC layer** follows Plan 9 philosophy correctly -- luciedit's filesystem at `/edit/` and lucishell's at `/tmp/veltro/shell/` let the AI read/write files while apps render/react.

4. **tools9p.b as a tool server** is smart -- exposing tools as a synthetic filesystem means the agent interacts with tools through file I/O, the same mechanism used for everything else.

## Where It's Clumsy

Two architectural patterns do similar things:

**Pattern A: Pure tools** -- Tool modules loaded by tools9p, implementing `tool.m`. Self-contained. The tool IS the capability.

**Pattern B: App wrappers** -- A GUI app runs independently, exposes a 9P filesystem, then a separate `tool.m` module acts as a thin wrapper that reads/writes that filesystem. The tool is a *proxy* for the real capability.

### Problems

1. **Lifecycle coupling** -- The lucishell *tool* only works if the lucishell *app* is running. If the app crashes or hasn't been started, the tool fails opaquely. No clean way for the tool to know the app's state.

2. **Duplicated naming/discovery** -- The app lives in `/dis/wm/lucishell.dis`, the tool in `/dis/veltro/tools/lucishell.dis`, and the 9P mount at `/tmp/veltro/shell/`. Three places to know about one thing.

3. **Inconsistent filesystem conventions** -- luciedit mounts at `/mnt/luciedit` (bound to `/edit/`), lucishell at `/tmp/veltro/shell/`, charon at `/tmp/veltro/browser/`, fractal at `/tmp/veltro/fractal/`. No consistent pattern.

4. **Wrapper boilerplate** -- Tools like `fractal.b` are essentially `read /tmp/veltro/fractal/ctl` and `write /tmp/veltro/fractal/ctl`. The tool.m wrapper adds indirection without value beyond semantic naming and doc strings.

5. **Security asymmetry** -- Headless tools are gated by namespace restriction on `/dis/veltro/tools/`. App-backed tools depend on *both* the tool being registered AND the app's 9P mount being accessible. Two security surfaces for one logical capability.

## Proposed Design

### Core Insight

Every capability the AI can use should be a 9P filesystem directory under `/tool/`, and `tools9p.b` should be the single registry and gateway.

### 1. Consistent `/tool/{name}/` Directory Convention

Every capability exposes:

```
/tool/{name}/
    doc       # read: returns tool documentation
    meta      # read: structured metadata (type, category)
    ctl       # read: current state; write: commands
    exec      # write: args; read: result (request/response tools)
    event     # read: blocking event stream (interactive tools only)
```

This replaces both `tool.m` (Limbo module interface) and the ad-hoc 9P mounts. `tools9p.b` already serves `/tool/{name}` -- extend from flat file per tool to directory per tool.

**For headless tools** (grep, exec, read): tools9p creates the directory and routes writes to `exec()` as today. The `doc` file serves documentation. No `event` file.

**For app-backed tools** (luciedit, charon): The app serves its own `/tool/{name}/` subtree via `file2chan`, or tools9p bind-mounts the app's 9P interface into `/tool/`. The app registers *directly* rather than going through a wrapper module.

### 2. Eliminate Wrapper Tool Modules

Instead of:
```
luciedit app → /mnt/luciedit/ (9P) → luciedit tool.m → /tool/luciedit (tools9p)
```

Do:
```
luciedit app → /tool/luciedit/ (direct bind or file2chan)
```

The app provides `doc`, `ctl`, `exec` files. When started, it registers into `/tool/`. When stopped, it unregisters. No proxy layer. Clean lifecycle.

### 3. Standardised Mount Convention

All capabilities under `/tool/{name}/`:

```
/tool/
    grep/doc, grep/exec                                        # headless
    luciedit/doc, luciedit/ctl, luciedit/exec, luciedit/event  # app-backed
    charon/doc, charon/ctl, charon/exec                        # app-backed
    fractal/doc, fractal/ctl                                   # app-backed
    tools                                                      # listing
    help                                                       # documentation
    _registry                                                  # internal
```

No more `/tmp/veltro/shell/`, `/tmp/veltro/fractal/`, `/mnt/luciedit/`.

### 4. App Registration Protocol

Apps register with tools9p:

```
# App writes to /tool/ctl:
register luciedit /mnt/luciedit

# tools9p bind-mounts /mnt/luciedit into /tool/luciedit
# and adds "luciedit" to the active tool list

# On app exit:
unregister luciedit
```

Or more idiomatically: apps serve file2chan entries directly under `/tool/{name}/` if tools9p supports union mounts.

### 5. Three Tool Types, One Interface

| Type | Description | Examples | Has `event`? |
|------|-------------|----------|-------------|
| **utility** | Headless, stateless, request/response | grep, read, write, exec, git | No |
| **service** | Headless, stateful, long-running | memory, todo, spawn | Optional |
| **app** | Has GUI, user-visible, collaborative | luciedit, lucishell, charon, fractal | Yes |

The `meta` file carries the type so the AI can distinguish "using luciedit will show the user something" from "using grep won't." Same calling convention regardless.

### 6. Capability Metadata in the Filesystem

The `meta` file replaces separate `.txt` files in `lib/veltro/tools/`:

```
type utility
category search
requires net
```

This lets `agentlib` build richer system prompts and lets `lucictx` display tools with appropriate visual treatment.

## Benefits

1. **Single discovery** -- `/tool/tools` lists everything. No hidden apps.
2. **Single security surface** -- Namespace restriction on `/tool/` gates all capabilities uniformly.
3. **No wrapper boilerplate** -- Apps register directly.
4. **Clean lifecycle** -- App not running means its `/tool/{name}/` doesn't exist. No opaque failures.
5. **Consistent conventions** -- Every tool at `/tool/{name}/` with the same file structure.
6. **Preserved strengths** -- `tool.m` still works for headless tools. 9P is still IPC. Namespace restriction still provides security. Semantic names still help the AI.

## Migration Path

1. **Phase 1**: Extend `tools9p.b` to serve directories instead of flat files. Existing `tool.m` modules work unchanged via wrapping.
2. **Phase 2**: Standardise app mounts under `/tool/{name}/`. Add `register`/`unregister` to `/tool/ctl`.
3. **Phase 3**: Delete wrapper tool modules (`appl/veltro/tools/luciedit.b`, `fractal.b`, etc.). Apps serve their own interfaces.
4. **Phase 4**: Add `meta` files. Update `agentlib` for richer prompt construction.

## Design Note: Plan 9 Purity vs AI Pragmatism

The purist approach: each app serves its own 9P filesystem, the agent interacts via file I/O, no tool abstraction.

The pragmatic need: LLMs need **semantic names and documentation** to know what tools do. Raw filesystem interfaces aren't self-describing enough for AI.

The `doc` and `meta` files bridge this -- they're the semantic layer that makes the filesystem AI-legible while keeping the architecture Plan 9-idiomatic. Use 9P for mechanism, doc/meta for semantics.
