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
2. factotum starts (with secstore backing if $SECSTORE_PASSWORD set, otherwise empty)
3. wm/logon displays login screen (skipped if keys already loaded or headless)
   - First boot: password + confirmation → creates secstore account
   - Normal boot: password → PAK auth → keys loaded into factotum
   - Wrong password: retry or continue without secstore
   - Escape (double-press): skip with warning
4. llmsrv, tools9p, wallet9p, lucibridge, lucifer start
5. System fully operational with all keys (wallet, API, email) available
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

A harness component: the shared configuration and execution server that running agents
dispatch tool calls through. Both the GUI (lucictx) and the GUI-side harness bridge
(lucibridge) interact with it as their common intermediary.

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

The GUI-side harness bridge: connects the GUI conversation UI to the LLM and runs the
agent loop for that session.

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

### wallet9p (`appl/veltro/wallet9p.b`)

Cryptocurrency wallet exposed as a 9P file server at `/n/wallet/`.

```
/n/wallet/
├── ctl              rw   "network <name>", "default <name>", "rpc <url>"
├── accounts         r    newline-separated account names
├── new              rw   write: "eth chain name" or "import eth chain name hexkey"
└── {name}/
    ├── address      r    public address (EIP-55 checksummed)
    ├── balance      r    live balance from blockchain RPC
    ├── chain        rw   chain name
    ├── sign         rw   write: hex hash → read: hex signature
    ├── pay          rw   write: "amount recipient" → read: txhash
    ├── ctl          rw   "budget maxpertx maxpersess currency"
    └── history      r    recent transactions
```

Key design properties:
- **Factotum-backed** — private keys stored in factotum (`service=wallet-eth-{name}`),
  never in wallet9p's memory. Signing writes a hash, reads back a signature.
- **Secstore persistence** — new accounts trigger factotum sync to secstore (async).
  Keys survive emu restart.
- **Budget enforcement** — server-side spending limits; agents cannot bypass.
- **Namespace-gated** — agents need `"/n/wallet"` in `caps.paths` to access. Unlike
  `/n/llm` (always granted), wallet access is explicitly opt-in.
- **Multi-network** — supports Ethereum Mainnet, Sepolia, Base, Base Sepolia with
  per-network RPC endpoints and USDC contract addresses.

### editor (`appl/wm/editor.b`)

Built-in text editor with 9P IPC for agent integration. Mounts at `/edit/`.

```
/edit/
├── ctl              rw   open <path>, new, quit
├── index            r    list of open document IDs
└── {id}/
    ├── body         rw   document text
    ├── ctl          rw   save, saveas, goto, find, insert, delete, replace, replaceall
    ├── addr         rw   cursor position ("line col")
    └── event        r    blocking read for events (modified, opened, quit)
```

The Veltro `editor` tool uses this IPC to let agents read, navigate, and modify open
documents without needing direct Draw access.

### Lucifer GUI (`appl/cmd/lucifer.b`)

Three-zone window: Conversation | Presentation | Context.

Starts the following pipeline:
1. `luciuisrv` — mounts at `/n/ui`
2. `tools9p` — mounts at `/tool` (with full default tool set)
3. `lucibridge` — connects conversation input → LLM → conversation output
4. `lucictx` — renders the context zone (tool toggles, namespace browser)

Additional features:
- **Live theme sync** — theme changes propagate to all running apps in real time
- **HiDPI fonts** — antialiased combined fonts for Retina/HiDPI displays
- **App slots** — up to 16 GUI apps (wallet, editor, fractals, etc.) in the presentation zone
- **Activity tracking** — per-activity event streams, status indicators, tool-call tiles

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
