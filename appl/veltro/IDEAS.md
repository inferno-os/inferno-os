# Veltro Ideas and Future Work

## Completed

### Phase 1a: Per-Agent LLM Isolation
- LLMConfig type in nsconstruct.m
- Session-specific model, temperature, system prompt, thinking budget
- Each subagent gets its own LLM session via `/n/llm/new` clone pattern
- 33 automated tests + 5 manual tests passing

### Phase 1b: mc9p (9P-based MCP)
- Filesystem-as-schema design (no JSON)
- Domain/endpoint model via synthetic files
- Network isolation (requires -n flag for /net access)
- HTTP provider working

### Phase 1c: New Tools
- **http** - HTTP client (HTTP working, HTTPS needs /net/ssl)
- **git** - Git operations (requires /cmd device)
- **json** - JSON parsing and path queries
- **ask** - User prompts via console
- **diff** - File comparison
- **memory** - Session persistence (basic implementation)
- **say** - Text-to-speech via speech9p
- **hear** - Speech-to-text via speech9p

### Phase 1d: Agent Memory
- Basic memory tool implemented
- Full cross-session persistence not yet tested

### Namespace v3: FORKNS + Bind-Replace
- `restrictdir(target, allowed)` core primitive (455 lines replaces 863)
- Root restriction hides project files (.env, .git, CLAUDE.md, source tree)
- `/n/local` (host filesystem) hidden via `/n` restriction
- `/n/speech` auto-detected and preserved for say/hear tools
- Three entry points: tools9p serveloop, repl init, spawn child
- tools9p restriction via non-blocking alt on buffered channel (avoids 9P deadlock)
- Root restriction skips stat() to avoid 9P self-mount deadlock on /tool
- Subagents use pre-loaded tool modules (not tools9p)
- Default agent prompt rewritten for pre-loaded module architecture
- Help file global storage fix (per-fid → global for cross-fid reads)
- Capability attenuation: children fork restricted parent, can only narrow
- verifyns() with positive and negative assertions

### Interactive REPL
- Xenith mode: window with Send/Voice/Clear/Reset/Delete buttons
- Terminal mode: line-oriented stdin/stdout
- Voice input via speech9p (record + transcribe)
- Session management (create, reset)
- Namespace discovery injected into each prompt
- Context-aware reminders based on available tools
- System prompt size guard (8KB 9P write limit)

### Agent Chaining (Subagents)
- spawn tool creates isolated children with attenuated capabilities
- Full agent loop in subagent (LLM access via pre-opened FDs)
- Agent type prompts: default, explore, plan, task
- LLM config per-agent: model, temperature, thinking, system prompt
- 2-minute timeout for multi-step agents (up to 50 steps)

---

## Usability Improvements

### Launcher Scripts

Create purpose-specific launcher scripts that preserve security while improving convenience.
The caller still explicitly chooses capabilities, but common configurations are pre-packaged.

**Example scripts:**

```sh
# /dis/veltro/launch/ui - For Xenith UI tasks
#!/dis/sh
tools9p read list xenith &
sleep 1
veltro $*

# /dis/veltro/launch/code - For code exploration
#!/dis/sh
tools9p read list find search &
sleep 1
veltro $*

# /dis/veltro/launch/edit - For code editing
#!/dis/sh
tools9p read list find search write edit &
sleep 1
veltro $*

# /dis/veltro/launch/full - All tools (trusted use only)
#!/dis/sh
tools9p read list find search write edit exec spawn xenith say hear &
sleep 1
veltro $*
```

### Xenith Integration

Add Xenith menu items or tag commands for launching Veltro:

1. **Tag commands** - Right-click menu items like "Veltro:UI", "Veltro:Code"
2. **Window action** - Button in Xenith toolbar to launch agent with context
3. **Plumber integration** - Plumb selected text to Veltro as a task

### Profile Integration

Add optional tools9p startup to profile for users who want always-available tools:

```sh
# In /lib/sh/profile (user's choice)
# Start minimal tool server for interactive Veltro use
tools9p read list &
```

**Note:** This is the user's security decision -- they choose what's always available.

---

## Tool Improvements

### Xenith Tool Enhancements

- **Batch operations** - Create multiple windows in one call
- **Templates** - Pre-configured window layouts (log viewer, code display, etc.)
- **Event subscription** - Tool to watch for window events (clicks, selections)
- **Clipboard integration** - Read/write system clipboard

### New Tools

- **test** - Run test suites from within agent
- **patch** - Apply unified diffs
- **tar** - Archive/extract files

---

## Architecture Ideas

### Tool Capability Levels

Define standard capability profiles:

| Level | Tools | Use Case |
|-------|-------|----------|
| readonly | read, list, find, search | Safe exploration |
| ui | readonly + xenith, say | Display results |
| write | ui + write, edit | Modify files |
| exec | write + exec | Run commands |
| full | exec + spawn | Create sub-agents |

### Persistent Tool Server

A system-wide tools9p that runs as a service:
- Started at boot
- Provides baseline tools to all agents
- Additional tools granted per-session via namespace overlays

**Security consideration:** Must not grant more than explicitly allowed.

### Path Restriction Improvements

Current path restriction via `caps.paths` exposes host filesystem paths through `/n/local`. Future work:
- Read-only vs read-write path grants
- Time-limited path access
- Path access logging/auditing

---

## Documentation

- Tutorial: "Your First Veltro Task"
- Guide: "Securing Veltro Deployments"
- Reference: Tool API documentation
- Examples: Common task patterns

---

## Performance

- Tool module caching (avoid reloading .dis files)
- Streaming results for large outputs
- Parallel tool execution where safe
