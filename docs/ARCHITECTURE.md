# Infernode / Veltro — Architecture

## Overview

Infernode is Inferno OS running natively on AMD64 and ARM64 (macOS, Linux, Windows). The AI
agent stack runs entirely inside the Inferno emulator (`emu`), using Plan 9's "everything is
a file" model to integrate the LLM API, tool execution, wallet, and GUI through a unified 9P namespace.

---

## Layer Diagram

```
Host OS (macOS / Linux / Windows)
│
├── emu (Dis VM + JIT compiler)
│     │
│     └── Inferno namespace (rootfs = project root)
│           │
│           ├── /n/llm        ← llmsrv (LLM providers as 9P)
│           ├── /n/ui         ← luciuisrv (GUI state 9P server)
│           ├── /n/wallet     ← wallet9p (crypto wallet 9P server)
│           ├── /tool         ← tools9p (39 tool modules as 9P)
│           ├── /mnt/factotum ← factotum (key agent, secstore-backed)
│           ├── /n/local/     ← agent-visible host paths (via sys->bind)
│           ├── /dis/         ← compiled Limbo bytecode (815 modules)
│           ├── /lib/         ← runtime data (fonts, tool docs, resources)
│           └── /tmp/         ← scratch (writable at /tmp/veltro/scratch/)
│
└── secstored (TCP 5356)      ← encrypted key persistence (AES-256-GCM)
```

## Boot Sequence

```
1. secstored starts (TCP port 5356)
2. factotum starts (empty, no keys)
3. wm/logon displays login screen (or skipped in headless mode)
4. User enters secstore password → PAK auth → keys loaded into factotum
5. llmsrv, tools9p, wallet9p, lucibridge, lucifer start
6. System fully operational with all keys (wallet, API, email) available
```

---

## Components

### llmsrv (native Limbo LLM service)

- Source: `appl/cmd/llmsrv.b`; runs inside Inferno emulator
- Presents LLM providers (Anthropic API or Ollama/OpenAI-compatible) as a 9P file server
- Self-mounts at `/n/llm`; can also be accessed remotely via 9P dial+mount
- Session lifecycle: clone from `/n/llm/new` → session directory `/n/llm/{id}/`
- Files per session: `ask` (write prompt → read response), `tools` (write tool schemas),
  `history` (full conversation history)
- Response format: `STOP:tool_use\nTOOL:<id>:<name>:<args>` or `STOP:end_turn\n<text>`
- Native `tool_use` protocol: LLM receives proper JSON tool schemas, returns structured tool calls

### tools9p (`appl/veltro/tools9p.b`)

The shared configuration and execution server for the agent stack. Both the GUI (lucictx)
and the agent bridge (lucibridge) interact with it as their common intermediary.

Filesystem layout at `/tool`:

```
/tool/
├── tools       (r)   Newline-separated list of currently active tool names
├── help        (rw)  Write tool name → read documentation
├── ctl         (rw)  Control: add/remove tools; bindpath/unbindpath paths
├── paths       (r)   Newline-separated list of registered namespace paths
└── _registry   (r)   Space-separated list of tool names (for spawn validation)
└── <name>      (rw)  Per-tool file: write args → blocking execute → read result
```

Key design properties:
- **Pre-loads all tool modules before namespace restriction** — allows `ctl add` without
  needing access to `/dis/veltro/tools/`
- **Async tool execution** — `asyncexec()` runs tool in a spawned goroutine; the write()
  call blocks until complete but the serveloop remains responsive to other 9P traffic
- **Shared server** — tools9p runs in its own Inferno thread and is mounted in the shell's
  namespace; both lucictx (GUI) and lucibridge (agent bridge) inherit `/tool` from there

### lucibridge (`appl/cmd/lucibridge.b`)

The agent bridge: connects the GUI conversation UI to the LLM.

- Runs in background, started by Lucifer
- Reads user input from `/n/ui/activity/{id}/conversation/input`
- On each turn: re-reads `/tool/tools` and `/tool/paths` to pick up GUI-side changes
- If tool set changed: calls `initsessiontools()` to update the LLM's active tool list
- If path set changed: calls `applypathchanges()` to bind/unmount paths in its namespace
- Sends LLM responses and streaming tokens back via `/n/ui/activity/{id}/conversation/ctl`

### luciuisrv (`appl/cmd/luciuisrv.b`)

GUI state server — a 9P file server for the three-zone Lucifer UI.

Mounted at `/n/ui`. Presents conversation messages, presentation artifacts, and context
zone state as a filesystem. No draw/display dependency — fully testable headless.

```
/n/ui/
├── ctl                           Global control
├── event                         Global event stream
├── catalog/                      Resource catalog (from /lib/veltro/resources/*.resource)
└── activity/{id}/
      ├── label                   Activity name
      ├── status                  idle / working / error
      ├── event                   Per-activity event stream
      ├── conversation/
      │     ├── ctl               Write messages / update streaming token
      │     ├── input             Blocking read: next user message
      │     └── {N}               Indexed message files
      ├── presentation/
      │     ├── ctl               Create / update / append / center artifacts
      │     ├── current           ID of centered artifact
      │     └── {id}/             Per-artifact directory
      │           ├── type        text / markdown / pdf / diagram
      │           ├── label       Display label
      │           └── data        Artifact content
      └── context/
            ├── ctl               Add resources / gaps / bg tasks
            ├── resources/{N}     Context resources
            ├── gaps/{N}          Knowledge gaps
            └── background/{N}    Background tasks
```

### Veltro (`appl/veltro/veltro.b`)

CLI agent. One-shot or REPL mode.

1. Reads `-p paths` and registers them in tools9p (`bindpath` ctl commands)
2. Forks namespace (`sys->pctl(FORKNS)`)
3. Calls `nsconstruct->restrictns()` — reduces namespace to only what the agent needs
4. Creates an LLM session via `/n/llm/new`
5. Runs `repl.b` loop: prompt → LLM → tool calls → results → repeat

### nsconstruct (`appl/veltro/nsconstruct.b`)

Namespace restriction engine, called by both tools9p and veltro.

Policy applied after `FORKNS`:
- `/dis` → reduced to `lib/`, `veltro/` (+ `sh.dis` if `exec` tool active)
- `/dis/veltro/tools/` → only registered tool `.dis` files visible
- `/dev` → reduced to `cons`, `null`, `time`
- `/n` → capability-gated: `/n/llm` always; `/n/git`, `/n/speech` only if in `caps.paths`
- `/tmp` → writable only at `/tmp/veltro/scratch/`

### Lucifer GUI (`appl/cmd/lucifer.b`)

Three-zone window: Conversation | Presentation | Context.

Starts the following pipeline:
1. `luciuisrv` — mounts at `/n/ui`
2. `tools9p` — mounts at `/tool` (with full default tool set)
3. `lucibridge` — connects conversation input → LLM → conversation output
4. `lucictx` — renders the context zone (tool toggles, namespace browser)

---

## Data Flows

### User sends a message

```
User types in Conversation zone
  → lucifer writes to /n/ui/activity/{id}/conversation/ctl
  → luciuisrv stores message, fires "conversation N" event
  → lucifer re-renders conversation zone
  → lucibridge (blocking read on /conversation/input) receives message
  → lucibridge re-reads /tool/tools, /tool/paths
  → lucibridge calls LLM via /n/llm/{id}/ask
  → LLM returns tool_use or end_turn
  → lucibridge executes tools (writes to /tool/<name>, reads result)
  → lucibridge writes response back to /n/ui conversation/ctl
  → lucifer renders response
```

### User toggles a tool in Context zone

```
User clicks [-] on "diff" in context zone
  → lucictx writes "remove diff" to /tool/ctl
  → tools9p moves diff from active set to alltools
  → /tool/tools no longer lists "diff"
  → On next LLM turn: lucibridge re-reads /tool/tools, calls initsessiontools()
  → LLM no longer receives diff tool schema
```

### User binds a directory via Context zone browser

```
User browses to /Users/pdfinn/docs, clicks [Bind]
  → lucictx writes "bindpath /Users/pdfinn/docs" to /tool/ctl
  → tools9p adds path to boundpaths list; /tool/paths now lists it
  → On next LLM turn: lucibridge reads /tool/paths, calls applypathchanges()
  → lucibridge: sys->bind("/Users/pdfinn/docs", "/n/local/docs", MBEFORE)
  → Agent can now read files under /n/local/docs
```

---

## Namespace Isolation Model

Each agent session has a restricted namespace:

```
Full Inferno namespace (shell, GUI)
  │
  ├── tools9p runs in this namespace (shared)
  └── FORKNS ──► Agent namespace (restricted copy)
                   ├── /n/llm          (always)
                   ├── /n/local/<base> (only granted paths)
                   ├── /tool           (inherited, read-only in practice)
                   ├── /dis/veltro/    (tool .dis files only)
                   ├── /dev/cons       (console only)
                   └── /tmp/veltro/scratch/  (only writable area)
```

Subagents (via `spawn` tool) can only NARROW further — they cannot re-grant permissions
their parent didn't have.

---

## Cross-Host

The same stack runs on Linux ARM64 (e.g. Jetson) over ZeroTier with Ed25519 authentication
and RC4-256 encryption. 9P mounts work cross-host: the remote Inferno namespace is
accessible locally via `mount -A tcp!<host>!<port> /n/remote`.

---

## Key Files

| Component | Source | Compiled |
|-----------|--------|----------|
| tools9p | `appl/veltro/tools9p.b` | `dis/veltro/tools9p.dis` |
| lucibridge | `appl/cmd/lucibridge.b` | `dis/lucibridge.dis` |
| lucictx | `appl/cmd/lucictx.b` | `dis/lucictx.dis` |
| lucifer | `appl/cmd/lucifer.b` | `dis/lucifer.dis` |
| luciuisrv | `appl/cmd/luciuisrv.b` | `dis/luciuisrv.dis` |
| lucitheme | `appl/cmd/lucitheme.b` | `dis/lucitheme.dis` |
| veltro | `appl/veltro/veltro.b` | `dis/veltro/veltro.dis` |
| nsconstruct | `appl/veltro/nsconstruct.b` | `dis/veltro/nsconstruct.dis` |
| agentlib | `appl/veltro/agentlib.b` | `dis/veltro/agentlib.dis` |
| llmsrv | `appl/cmd/llmsrv.b` | `dis/llmsrv.dis` |
| wallet9p | `appl/veltro/wallet9p.b` | `dis/veltro/wallet9p.dis` |
| factotum | `appl/cmd/auth/factotum/factotum.b` | `dis/auth/factotum.dis` |
| secstored | `appl/cmd/auth/secstored.b` | `dis/auth/secstored.dis` |
| logon | `appl/wm/logon.b` | `dis/wm/logon.dis` |
| editor | `appl/wm/editor.b` | `dis/wm/editor.dis` |
