# Welcome to Infernode

You are running **Infernode** — a modern fork of Bell Labs' Inferno OS
with an AI agent and a graphical environment built in.

## What you are looking at

**Lucifer** is the three-zone interface in front of you:

- **Left — Conversation.** This is where you talk to me. Type a message
  and press Enter (or click Send).
- **Centre — Presentation.** Documents, code, images, fractals, a text
  editor, a shell — anything I show you or you launch appears here as
  a tab.
- **Right — Context.** Your active tools, bound directories, knowledge
  gaps, and background tasks. Toggle tools on or off; bind host
  directories to give me access.

I am **Veltro**, the AI agent native to this system. I can read and
write files, search code, launch apps, speak aloud, remember things
across sessions, browse the web, send email, draw fractals, and more.
Everything I do is visible — my tools are files, my actions show up in
your workspace.

## Things to try

**Talk to me.** Ask a question, give me a task, or just say hello.

**Launch an app.** Ask me to:
- `launch luciedit` — a text editor in the presentation zone
- `launch lucishell` — a shell terminal
- `launch mand` — the Mandelbrot fractal viewer (I can drive it too)
- `launch clock` — a clock
- `launch xenith` — the full Xenith text environment (Acme descendant)

**Explore the system.** Ask me to show you what's in `/appl` or
`/module`, or to explain how the namespace works.

**Run the guided tour.** Say **"run the tour"** and I will walk you
through the system interactively — opening windows, demonstrating tools,
and letting you try things hands-on.

## Key concepts

**Everything is a file.** Windows, the LLM, speech, tools — all exposed
as files in a 9P namespace. There are no APIs, only filesystems.

**Namespace is security.** If a path is not in your namespace, it does
not exist. I run in a restricted namespace — you control what I can see
via the Context zone.

**Shared workspace.** I see what you see. Your open documents are our
shared working surface.

## Quick reference

| Action | How |
|--------|-----|
| Talk to me | Type in the Conversation zone |
| Launch an app | Ask me, or middle-click a command |
| Open a file | Right-click a path, or ask me |
| Toggle my tools | Click [+]/[-] in the Context zone |
| Give me file access | Bind a directory in the Context zone |
| Full reference | Ask me to open `/lib/guide` |
| Comprehensive manual | Ask me to open `/docs/USER-MANUAL.md` |

---

*Say "run the tour" for a hands-on guided demonstration.*
