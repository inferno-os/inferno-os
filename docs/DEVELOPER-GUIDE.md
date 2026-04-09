# Developer Guide: Running, Debugging, and Resetting InferNode

This guide covers running InferNode from the command line for development,
debugging, and testing. For building from source, see QUICKSTART.md. For
the testing framework, see the Testing System section in CLAUDE.md.

## Running from the Command Line

### Minimal Startup (Interpreter Only, No GUI)

```sh
cd infernode
./emu/MacOSX/o.emu -r. sh -l
```

This starts the Inferno shell with your profile loaded (`-l`). You get a
text console — no GUI, no agent, no LLM.

### Full GUI Startup

```sh
cd infernode/emu/MacOSX
./o.emu -c1 -pheap=1024m -pmain=1024m -pimage=1024m -r../.. \
  sh -l -c "wm/logon; \
    llmsrv &; sleep 1; \
    /dis/veltro/wallet9p.dis &; sleep 1; \
    luciuisrv; \
    echo activity create Main > /n/ui/ctl; sleep 1; \
    /dis/veltro/tools9p -v -m /tool \
      -b read,list,find,search,grep,write,edit,editor,exec,launch,spawn,diff,json,fractal,webfetch,git,say,memory,todo,plan,websearch,mail,keyring,present,gap \
      -p /dis/wm read list find present say hear task memory gap keyring editor shell; \
    lucibridge -a 0 -v -s &; sleep 1; \
    echo 'create id=tasks type=taskboard label=Tasks' > /n/ui/activity/0/presentation/ctl; \
    lucifer"
```

This is equivalent to what the app bundle does via `lib/sh/profile` and
`lib/lucifer/boot.sh`, but laid out explicitly so you can see and modify
each step.

### Breaking Down the Command

**Emulator flags:**

| Flag | Purpose |
|------|---------|
| `-c1` | Enable JIT compilation (ARM64 or AMD64). Use `-c0` for interpreter only. |
| `-pheap=1024m` | Heap pool size (memory for Limbo allocations) |
| `-pmain=1024m` | Main pool size (memory for kernel data structures) |
| `-pimage=1024m` | Image pool size (memory for draw images/GUI) |
| `-r../..` | Inferno root directory. Points to the project checkout. The path is concatenated directly to `-r` with no space. |

**Boot sequence (inside `sh -l -c "..."`):**

The `-l` flag loads `lib/sh/profile` which sets up networking, the host
filesystem mount (`trfs`), the `~/.infernode` writable overlay, secstored,
and factotum. Then `-c` runs the quoted command string:

| Step | Command | Purpose |
|------|---------|---------|
| 1 | `wm/logon` | Login screen. Creates secstore account on first run, unlocks and loads keys on subsequent runs. Blocks until the user enters their password. |
| 2 | `llmsrv &` | LLM 9P file server. Mounts at `/n/llm`. Reads config from `lib/ndb/llm` (via profile). The `&` backgrounds it. |
| 3 | `wallet9p &` | Cryptocurrency wallet 9P server. Experimental. |
| 4 | `luciuisrv` | UI 9P server. Creates the `/n/ui` namespace that lucifer, lucipres, luciconv, and lucibridge all communicate through. This is the hub. |
| 5 | `echo activity create Main > /n/ui/ctl` | Creates the default "Main" activity (task/conversation). |
| 6 | `tools9p -v -m /tool -b ... -p ...` | Veltro tool server. `-b` lists built-in tool modules. `-p` lists tools available to the agent as "passive" (invocable). Mounts at `/tool`. |
| 7 | `lucibridge -a 0 -v -s &` | Agent bridge. Connects the conversation zone to the LLM. `-a 0` targets activity 0, `-v` verbose, `-s` enables speech. |
| 8 | `echo 'create id=tasks ...' > /n/ui/...` | Creates the Tasks taskboard tab in the presentation zone. |
| 9 | `lucifer` | Main GUI. Blocks until the user exits. When lucifer returns, emu shuts down. |

**Important:** Commands are separated by `;` not `&&`. The Inferno shell
is rc-style and does not support `&&` or `||` operators.

### Capturing Logs

The app bundle suppresses stderr. To see diagnostic output:

```sh
/path/to/InferNode.app/Contents/MacOS/InferNode 2>/tmp/infernode.log
```

Or from a dev checkout:

```sh
cd infernode/emu/MacOSX
./o.emu -c1 -pheap=1024m -pmain=1024m -pimage=1024m -r../.. \
  sh -l /lib/lucifer/boot.sh 2>/tmp/infernode.log
```

Key log messages to look for:

| Message | Meaning |
|---------|---------|
| `logon: loaded N keys from secstore` | Secstore unlocked successfully, N keys restored |
| `logon: secstore has no factotum file` | No saved keys (first run or read failure) |
| `factotum: secstore configured` | Save-back to secstore is active |
| `lucibridge: ready` | Agent is connected and waiting for input |
| `lucibridge: llm configured but not ready` | LLM service failed to start |
| `tools9p: warning: cannot load tool X` | A tool's .dis file is missing (rebuild needed) |

### Running Without the Agent

To test the GUI without Veltro/LLM (useful for UI work):

```sh
cd infernode/emu/MacOSX
./o.emu -c1 -pheap=1024m -pmain=1024m -pimage=1024m -r../.. \
  sh -l -c "wm/logon; luciuisrv; echo activity create Main > /n/ui/ctl; sleep 1; lucifer"
```

This starts logon, the UI server, and lucifer — but no llmsrv, no
lucibridge, no tools9p. The conversation zone will be empty.

## The ~/.infernode Directory

InferNode stores all user data in `~/.infernode`, separate from the
read-only emu root (whether that's an app bundle or a dev checkout).
The profile creates this directory on first run and bind-mounts its
subdirectories over the corresponding paths in the Inferno namespace.

### Directory Structure

```
~/.infernode/
  usr/inferno/secstore/     # Encrypted key storage (PAK + factotum files)
  usr/inferno/tmp/           # Persistent temp files
  lib/ndb/                   # LLM config (lib/ndb/llm)
  lib/lucifer/theme/         # GUI theme (current)
  lib/veltro/                # Agent state (welcome_shown, tour_offered, meta.txt)
  lib/veltro-agents/         # Task agent prompts
  lib/veltro-keys/           # Agent API keys
  tmp/                       # Session temp files
```

### How It Works

The profile (`lib/sh/profile`) uses `bind -bc` to overlay each
`~/.infernode` subdirectory onto the corresponding Inferno path:

```
bind -bc ~/.infernode/usr/inferno/secstore  /usr/inferno/secstore
bind -bc ~/.infernode/lib/ndb               /lib/ndb
bind -bc ~/.infernode/lib/veltro            /lib/veltro
...
```

The `-bc` flags mean: **b**efore (overlay takes priority over the
original) and **c**reate (new files go to the overlay, not the original).
This means writes always go to `~/.infernode` while reads fall through
to the emu root for defaults.

### Why It Exists

Without the overlay, user data would be written into the emu root.
In an app bundle, the emu root is inside the signed `.app` — read-only.
Even in a dev checkout, mixing user data with source code is messy.
The overlay keeps the emu root clean and user state portable.

## Resetting

### Reset the Guided Tour

The tour is offered once per installation. To see it again:

```sh
rm ~/.infernode/lib/veltro/tour_offered
```

On next launch, Veltro will offer the guided tour again.

### Reset the Welcome Message

```sh
rm ~/.infernode/lib/veltro/welcome_shown
```

### Full Reset (Start Fresh)

**WARNING: This deletes your secstore password, all saved API keys,
LLM configuration, theme, and agent state. You will need to set up
everything from scratch on next launch.**

```sh
rm -rf ~/.infernode
```

On next launch, the profile detects the missing directory, recreates
it, seeds defaults, and the login screen shows the first-run setup.

### Reset Only Secstore (Keep Config)

To clear saved keys without wiping everything:

```sh
rm -rf ~/.infernode/usr/inferno/secstore
```

On next launch, logon will show the first-run password setup.

## Debugging Common Issues

### "Launching..." Stuck on App Tab

The app's .dis file may be stale (compiled against an old module
interface). Rebuild:

```sh
export ROOT=$PWD PATH=$PWD/MacOSX/arm64/bin:$PATH
cd appl/cmd && mk install    # or the specific directory
```

### Blank Conversation Zone / "LLM configured but not ready"

llmsrv failed to start. Common causes:

- **No API key:** Add one via Keyring, or set `ANTHROPIC_API_KEY` env var
- **Wrong backend:** Check `~/.infernode/lib/ndb/llm` — `backend=openai`
  needs a URL like `http://127.0.0.1:11434/v1` (not `localhost`)
- **Model doesn't support tools:** Use a tool-capable model (llama3.2,
  qwen2.5, mistral) — llama2 does not support tools and returns empty

### Login Asks for Password Setup Again

The secstore overlay may not have loaded. Check:

```sh
ls ~/.infernode/usr/inferno/secstore/$(whoami)/PAK
```

If PAK exists, it's a trfs timing issue (see boot.sh warmup). If it
doesn't exist, secstore wasn't saved — you'll need to set up again.

### "link typecheck" Errors

A `.dis` file was compiled against an old `.m` interface. Rebuild
the affected directory:

```sh
export ROOT=$PWD PATH=$PWD/MacOSX/arm64/bin:$PATH
cd appl/xenith && mk install    # if xenith modules changed
cd appl/cmd && mk install       # if cmd modules changed
```

See the "Stale bytecode problem" section in CLAUDE.md for details.

### Tests Fail With "cannot load testing module"

The testing framework .dis is missing or stale:

```sh
export ROOT=$PWD PATH=$PWD/MacOSX/arm64/bin:$PATH
cd appl/lib && mk testing.dis
cd tests && mk install
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | API key fallback (used if not in secstore) |
| `SECSTORE_PASSWORD` | Headless mode: auto-unlock secstore without login screen |
| `OLLAMA_HOST` | Not used by InferNode — configure via Settings or `lib/ndb/llm` |

## Platform Notes

### macOS (Apple Silicon)

- Emulator binary: `emu/MacOSX/o.emu` (or `InferNode.app/Contents/MacOS/emu`)
- Native tools: `MacOSX/arm64/bin/mk`, `MacOSX/arm64/bin/limbo`
- JIT: ARM64 JIT with `-c1`

### Linux (AMD64)

- Build: `./build-linux-amd64.sh`
- Emulator binary: `emu/Linux/o.emu`
- Native tools: `Linux/amd64/bin/mk`, `Linux/amd64/bin/limbo`
- JIT: AMD64 JIT with `-c1`

### Linux (ARM64, e.g. NVIDIA Jetson)

- Build: `./build-linux-arm64.sh`
- Native tools: `Linux/arm64/bin/mk`, `Linux/arm64/bin/limbo`
- JIT: ARM64 JIT with `-c1`
