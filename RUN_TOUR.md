# Running the Veltro Tour

The tour is an interactive demonstration that runs **inside** Infernode, where Veltro (the AI agent) uses its native tools to walk you through the system.

## Quick Start (Lucifer GUI)

The recommended way to experience the tour is through Lucifer, the three-zone GUI. When Lucifer launches, a welcome document loads in the presentation zone. From the conversation zone, say:

```
run the tour
```

Veltro will create artifacts in the presentation zone, launch apps, demonstrate tools, and guide you through the system interactively.

## Quick Start (Terminal / Xenith)

From the infernode directory:

```sh
# Set up environment
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH

# Start Infernode
./emu/MacOSX/o.emu -r. -c1
```

Once inside Inferno, at the `;` prompt:

```sh
; veltro 'run the tour'
```

Or start the REPL and ask for the tour:

```sh
; repl
> run the tour
```

## What the Tour Demonstrates

The tour shows Veltro using its tools to demonstrate:

1. **The three zones** — Conversation, Presentation, and Context
2. **Everything is a file** — Namespace exploration (/tool, /n/llm, /n/ui)
3. **Launching apps** — Clock, editor, shell, fractal viewer in the presentation zone
4. **The fractal viewer** — Mandelbrot/Julia exploration driven by AI
5. **The text editor** — Luciedit for collaborative editing
6. **Finding and reading files** — Code navigation with find, read, search, grep
7. **The Context zone** — Tool toggles, path binding, knowledge gaps
8. **Persistence** — Memory across sessions
9. **Voice** — Text-to-speech and speech-to-text
10. **Host OS bridge** — Accessing the host system
11. **Subagents and security** — Isolated agents with namespace capabilities
12. **More capabilities** — Todo, HTTP, mail, git, vision, web search
13. **Next steps** — Where to go from here

## Welcome Document

On first launch, Lucifer displays `/lib/veltro/welcome.md` in the presentation zone. This introduces the three-zone layout, lists things to try, and invites the user to run the tour.

## Tour Location

The tour script is at: `/lib/veltro/demos/tour.txt`

Veltro reads this script and executes it interactively, using `present`, `launch`, `say`, `fractal`, `luciedit`, `list`, `read`, `find`, `search`, `exec`, `memory`, `gap`, and `ask` tools to demonstrate the system live.

## Requirements

- Infernode emulator running
- For Lucifer tour: Lucifer GUI active (recommended)
- For terminal tour: Xenith or terminal mode
- Optional: speech system for text-to-speech (`say` tool)

## Notes

The tour is **interactive** — Veltro pauses between sections and asks if you want to continue, repeat, or skip ahead. It launches real apps, draws real fractals, and creates real artifacts. It's designed to be hands-on, not just informational.
