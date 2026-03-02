# Running the Veltro Tour

The tour is an interactive demonstration that runs **inside** Infernode, where Veltro (the AI agent) can use its native tools.

## Quick Start

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

1. **Xenith** - The text environment (Acme descendant)
2. **Everything is a file** - Namespace exploration
3. **Workspace awareness** - Veltro sees your open windows
4. **Window status colors** - Visual feedback
5. **Finding and reading files** - Code navigation
6. **Persistence** - Memory across sessions
7. **Voice** - Text-to-speech and speech-to-text
8. **Host OS bridge** - Accessing the host system
9. **Subagents** - Isolated agents with namespace security
10. **Next steps** - Where to go from here

## Tour Location

The tour script is at: `/lib/veltro/demos/tour.txt`

Veltro reads this script and executes it interactively, using the `say`, `xenith`, `list`, `read`, `find`, `search`, `exec`, and `memory` tools to demonstrate the system live.

## Requirements

- Infernode emulator running
- Xenith window system active (starts automatically)
- Optional: speech system for text-to-speech (`say` tool)

## Notes

The tour is **interactive** - Veltro will pause between sections and ask if you want to continue, repeat, or skip ahead. It's designed to be hands-on, not just informational.
