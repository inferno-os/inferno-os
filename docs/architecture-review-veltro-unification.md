# Veltro Architecture Review: Tool/App Unification

## Current State

Three categories of AI-accessible capabilities exist:

| Category | Examples | Interface | Discovery | Security |
|----------|----------|-----------|-----------|----------|
| **Headless tools** | exec, grep, read, write, git | `tool.m` (init/name/doc/exec) | `/tool/tools` listing | Namespace restriction on `/dis/veltro/tools/` |
| **App-backed tools** | lucishell, edit, charon, fractal | Tool wraps 9P filesystem at `/tmp/veltro/{app}/` | Same `/tool/tools` listing | Tool registration + app must be running |
| **Lucifer zone apps** | luciconv, lucipres, lucictx | 9P at `/n/ui/` | Implicit (always present) | Part of Lucifer lifecycle |

## What Works Well

1. **`tool.m` is clean** -- four functions (`init`, `name`, `doc`, `exec`) is a good minimal interface. The AI gets a uniform call pattern regardless of what's behind it.

2. **Namespace = capability** is elegant -- `nsconstruct.b`'s shadow-directory approach and the `Capabilities` ADT are architecturally sound. Removing a tool from `/dis/veltro/tools/` makes it invisible to the agent.

3. **9P as the IPC layer** follows Plan 9 philosophy correctly -- edit's filesystem at `/edit/` and lucishell's at `/tmp/veltro/shell/` let the AI read/write files while apps render/react.

4. **tools9p.b as a tool server** is smart -- exposing tools as a synthetic filesystem means the agent interacts with tools through file I/O, the same mechanism used for everything else.

## Where It's Clumsy

Two architectural patterns do similar things:

**Pattern A: Pure tools** -- Tool modules loaded by tools9p, implementing `tool.m`. Self-contained. The tool IS the capability.

**Pattern B: App wrappers** -- A GUI app runs independently, exposes a 9P filesystem, then a separate `tool.m` module acts as a thin wrapper that reads/writes that filesystem. The tool is a *proxy* for the real capability.

### Problems

1. **Lifecycle coupling** -- The lucishell *tool* only works if the lucishell *app* is running. If the app crashes or hasn't been started, the tool fails opaquely. No clean way for the tool to know the app's state.

2. **Duplicated naming/discovery** -- The app lives in `/dis/wm/lucishell.dis`, the tool in `/dis/veltro/tools/lucishell.dis`, and the 9P mount at `/tmp/veltro/shell/`. Three places to know about one thing.

3. **Inconsistent filesystem conventions** -- edit mounts at `/mnt/edit` (bound to `/edit/`), lucishell at `/tmp/veltro/shell/`, charon at `/tmp/veltro/browser/`, fractal at `/tmp/veltro/fractal/`. No consistent pattern.

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

**For app-backed tools** (edit, charon): The app serves its own `/tool/{name}/` subtree via `file2chan`, or tools9p bind-mounts the app's 9P interface into `/tool/`. The app registers *directly* rather than going through a wrapper module.

### 2. Eliminate Wrapper Tool Modules

Instead of:
```
edit app → /mnt/edit/ (9P) → edit tool.m → /tool/edit (tools9p)
```

Do:
```
edit app → /tool/edit/ (direct bind or file2chan)
```

The app provides `doc`, `ctl`, `exec` files. When started, it registers into `/tool/`. When stopped, it unregisters. No proxy layer. Clean lifecycle.

### 3. Standardised Mount Convention

All capabilities under `/tool/{name}/`:

```
/tool/
    grep/doc, grep/exec                                        # headless
    edit/doc, edit/ctl, edit/exec, edit/event  # app-backed
    charon/doc, charon/ctl, charon/exec                        # app-backed
    fractal/doc, fractal/ctl                                   # app-backed
    tools                                                      # listing
    help                                                       # documentation
    _registry                                                  # internal
```

No more `/tmp/veltro/shell/`, `/tmp/veltro/fractal/`, `/mnt/edit/`.

### 4. App Registration Protocol

Apps register with tools9p:

```
# App writes to /tool/ctl:
register edit /mnt/edit

# tools9p bind-mounts /mnt/edit into /tool/edit
# and adds "edit" to the active tool list

# On app exit:
unregister edit
```

Or more idiomatically: apps serve file2chan entries directly under `/tool/{name}/` if tools9p supports union mounts.

### 5. Three Tool Types, One Interface

| Type | Description | Examples | Has `event`? |
|------|-------------|----------|-------------|
| **utility** | Headless, stateless, request/response | grep, read, write, exec, git | No |
| **service** | Headless, stateful, long-running | memory, todo, spawn | Optional |
| **app** | Has GUI, user-visible, collaborative | edit, lucishell, charon, fractal | Yes |

The `meta` file carries the type so the AI can distinguish "using edit will show the user something" from "using grep won't." Same calling convention regardless.

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
3. **Phase 3**: Delete wrapper tool modules (`appl/veltro/tools/edit.b`, `fractal.b`, etc.). Apps serve their own interfaces.
4. **Phase 4**: Add `meta` files. Update `agentlib` for richer prompt construction.

## Forward-Looking: GUI/Headless Duality

The vision: every tool should be operable by the AI in both GUI and headless modes. The user may be watching (GUI) or absent (headless). The AI's interface shouldn't change.

### Why the unified `/tool/{name}/` design enables this

The 9P filesystem interface is display-agnostic. When a GUI app like Charon serves `/tool/charon/exec`, the AI writes a URL, reads back rendered content. Whether Charon also draws pixels to a window is orthogonal -- it's a rendering concern, not an interface concern.

This means:

1. **App-backed tools become headless-capable by default** if they serve their full functionality through `/tool/{name}/`. Charon can browse, scrape, and export without a display. The fractal app can explore parameter space and export images. The tool interface is the same either way.

2. **The `meta` file's `type` field** distinguishes "this tool has a visual component" from "this tool is purely headless" -- but the calling convention is identical. The AI doesn't need different code paths for GUI vs headless.

3. **GUI is additive, not required.** An app starts serving its `/tool/{name}/` directory. If a display is available, it also renders. The 9P interface is the primary; the GUI is a secondary presentation layer.

### What this requires from apps

Apps that want to be AI-drivable headlessly must:
- Serve their complete functionality via `/tool/{name}/` files, not just a thin control surface
- Not assume a display is attached for core operations
- Use the `event` file for streaming state changes the AI can consume without polling

This is already natural for apps built on Inferno's `file2chan` -- the filesystem IS the API.

## Forward-Looking: Auto-Coding Layer

The end state: the AI can compose new tools from available Limbo modules, compile them, register them dynamically, and use them -- all without human intervention.

### Why the current architecture supports this

The pieces already exist:

1. **`exec` tool** -- can invoke the `limbo` compiler on generated source
2. **`/tool/ctl add`** -- dynamic tool registration at runtime
3. **`tool.m`** -- the four-function contract is simple enough for an AI to implement
4. **Module interfaces (`*.m`)** -- self-documenting contracts the AI can read and compose

### What auto-coding looks like

```
1. AI identifies need for a new capability (e.g., "parse CSV files")
2. AI reads relevant module interfaces (/module/bufio.m, /module/string.m)
3. AI writes a new tool implementing tool.m: /tmp/csvparse.b
4. AI invokes limbo compiler via exec: limbo -o /dis/veltro/tools/csvparse.dis /tmp/csvparse.b
5. AI registers the tool: write "add csvparse" to /tool/ctl
6. AI uses the tool: write args to /tool/csvparse, read result
```

### What the architecture needs to enable this

- **Phase 1 (current)**: The AI can already write code and invoke the compiler via `exec`. Manual process.
- **Phase 2**: A dedicated `compose` or `create` tool that handles the compile-register lifecycle, with appropriate sandboxing (the new tool's namespace is restricted by the creating agent's capabilities -- you can't escalate privileges by writing code).
- **Phase 3**: The AI can introspect available modules, read their interfaces, and generate correct Limbo code that type-checks. The module system provides the contracts; the AI provides the composition.

The security model handles this naturally: a composed tool inherits the creating agent's namespace restrictions. You can't write a tool that accesses `/n/git` if your namespace doesn't include it. Capability attenuation is preserved even through code generation.

## Design Note: The Semantic Shim as Temporary Adapter

### Current reality

LLMs today are trained on JSON, REST APIs, and function-calling conventions. They expect:
```json
{"name": "read", "input": {"args": "/path/to/file"}}
```

So `agentlib.b` translates between the 9P filesystem interface and the JSON tool_use protocol. This is the **semantic shim**: `buildtooldefs()` generates JSON schemas, `calltool()` translates tool_use calls into filesystem writes, `buildtoolresults()` packages results back into JSON.

### Why it should be cleanly separable

A future LLM trained natively on Plan 9-style filesystem interaction wouldn't need any of this. It would simply:
```
open /tool/read/exec
write /path/to/file
read → (file contents)
```

No JSON wrapping. No tool definitions. No `agentlib` translation layer. The filesystem IS the API.

### Architectural implication

The semantic shim (`agentlib.b`'s tool-related functions) should be treated as a **replaceable adapter layer**, not load-bearing architecture:

1. **Keep `tools9p.b` and the `/tool/` filesystem self-sufficient.** It should work perfectly without `agentlib` -- a Plan 9-native client should be able to use tools by reading and writing files directly. Don't let agentlib's needs contaminate tools9p's design.

2. **Keep tool documentation in the filesystem** (`/tool/{name}/doc`), not only in agentlib's hard-coded `tooldesc()` function. The doc files serve both current LLMs (via agentlib reading them into prompts) and future LLMs (reading them directly). This is already partly true with `/lib/veltro/tools/*.txt`, but unifying into `/tool/{name}/doc` makes it filesystem-native.

3. **Don't couple tool discovery to JSON generation.** Today `buildtooldefs()` both discovers tools and generates JSON. These should be separable: discovery is reading `/tool/tools`, JSON generation is the adapter's job.

4. **The `/tool/` filesystem convention IS the long-term API.** Everything else -- JSON schemas, tool_use protocol, system prompt injection -- is adapter code for current-generation LLMs. Design the filesystem interface as if the adapter will be removed, because eventually it should be.

### The stripping path

When a Plan 9-native LLM becomes available:

1. Strip `buildtooldefs()`, `buildtoolresults()`, and the tool_use parsing from `agentlib`
2. The LLM reads `/tool/tools`, opens `/tool/{name}/doc`, writes to `/tool/{name}/exec`, reads results
3. `tools9p.b` is unchanged -- it was always the real interface
4. System prompts shrink dramatically (no tool schemas, no exec syntax warnings)
5. The `reminders/` and tool docs become files the LLM reads on demand rather than content injected into prompts

The cleaner the separation today, the easier this future transition becomes.
