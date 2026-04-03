# Matrix: Compositional Module Runtime

## What Matrix Is

Matrix is a compositional module runtime for InferNode. It loads,
connects, and manages Limbo modules that interact with mounted 9P
services. Modules can be visual (drawing into a GUI pane) or headless
(running as background services). A composition -- the description of
which modules to load, what they mount, and how they are arranged --
is a plain text file.

Matrix in the sense of a substrate: the womb from which operational
configurations are born, grown, and crystallised into reusable
infrastructure.

A Matrix composition can be:

- A **live dashboard** -- display modules showing portfolio data, signal
  feeds, risk metrics, rendered in Lucifer's presentation zone.

- A **headless server** -- service modules processing data, watching
  thresholds, bridging systems, with no GUI at all.

- A **hybrid** -- display modules for the human, service modules for the
  agent, running side by side.

- An **agent-to-agent service** -- a crystallised composition served over
  9P, mounted and consumed by another agent's Veltro, with no human in
  the loop.

The compositional model, the text file format, the module library, and
the crystallisation process are identical in every case. The GUI is one
possible surface. The filesystem is the actual interface.


## Why Matrix Exists

InferNode's architecture makes everything a file. 9P services expose
structured data as directories and files. Veltro reasons about files.
What is missing is a way to compose modules into living configurations
that persist beyond a single Veltro utterance and that can be saved,
shared, evolved, and served.

Veltro can generate Markdown artifacts, but these are static snapshots --
stale the moment they render, and inconsistent across regenerations. A
conventional dashboard solves liveness but is rigid. A hand-written
server solves the headless case but is not composable or reusable.

Matrix occupies the space between all of these. Modules are live (they
read from 9P and update continuously). Compositions are flexible (Veltro
assembles them at runtime). The module interface is constrained enough
that compositions are reliable and reproducible. And the same composition
can run with a GUI, without one, or be served to another agent -- because
the foundation is the filesystem, not the screen.


## Architecture

### Runtime Modes

Matrix operates in two modes depending on whether any display modules
are present in the composition:

**GUI mode** -- When at least one display module is loaded, Matrix joins
Lucifer's wmsrv as a presentation-zone client. It receives a window on
the presentation Screen and manages the layout of display module regions
within it. Service modules run in the background. This is the mode a
human operator sees.

**Headless mode** -- When a composition contains only service modules,
Matrix runs without joining wmsrv. No window, no drawing, no GUI
dependency. If Lucifer is present, it may show a status tile indicating
the composition is running (name, module count, uptime). If Lucifer is
not present (e.g., a headless InferNode instance), Matrix runs as a pure
background process.

The same composition file, the same module loading, the same 9P namespace.
The only difference is whether `draw()` gets called.

### Where Matrix Lives (GUI Mode)

```
Lucifer
  +-- Conversation zone (left)
  +-- Presentation zone (centre)
  |     +-- Tab strip (managed by Lucifer)
  |     +-- Content area
  |           +-- Matrix pane (when active)
  |                 +-- Layout tree of display modules
  |                 +-- Background service modules
  +-- Context zone (right)
```

### Where Matrix Lives (Headless Mode)

```
InferNode namespace
  +-- /n/matrix/         # Matrix 9P filesystem (always present)
  |     +-- ctl
  |     +-- composition
  |     +-- modules/
  |     +-- library/
  +-- /n/tbl4/           # Mounted data source (example)
  +-- ...
```

No Lucifer required. Veltro (or any process) controls Matrix through
`/n/matrix/ctl`. Another agent on another machine mounts `/n/matrix/`
and interacts with the composition's service modules through the
filesystem.

### Relationship to Existing Infrastructure

Matrix builds on, not beside, what InferNode already provides:

- **widget.m** -- The standard widget toolkit (Scrollbar, Textfield,
  Listbox, Button, Label, Checkbox, Radio, Dropdown, Statusbar). Display
  modules use these to build their UI. No parallel widget system.

- **Renderer / Render** -- The dynamic module loading pattern (register,
  probe, load, call). Matrix follows the same idiom: modules are `.dis`
  files loaded at runtime via the standard Limbo `load` statement,
  type-checked by the Dis VM at load time.

- **lucitheme** -- Display modules inherit the active Lucifer theme. All
  colours come from `lucitheme`. Modules do not define their own palettes.

- **wmsrv** -- In GUI mode, Matrix is a well-behaved wmsrv client. It
  does not replace or bypass Lucifer's window management.

- **9P** -- Modules access data exclusively through the namespace. Matrix
  exposes its own state as a 9P filesystem. All external control is done
  by reading and writing files.


## Core Concepts

### Modules

A module is a Limbo `.dis` file that implements one of two interfaces:
**display** or **service**.

**Display modules** receive a rectangle within the Matrix pane, a mount
point in the namespace, and access to the Draw display. They render live
content using the widget.m toolkit and the standard Draw primitives. They
update when the Matrix runtime calls their `update` function.

**Service modules** receive a mount point but no rectangle. They run in
the background, reading from their mount and writing results to their own
directory in the Matrix namespace (e.g., alerts, transformed data,
computed state). Other modules, Veltro, or remote agents read these
outputs.

Both types are loaded and unloaded by the Matrix runtime. Both are
sandboxed by namespace: a module sees its mount point and the Matrix
control namespace, nothing else unless explicitly bound.

A composition can contain any mix of display and service modules,
including none of one type.

### Compositions

A composition is a text file that describes a Matrix configuration: which
modules to load, where they mount, and (if display modules are present)
how they are arranged. It is the complete, portable, reproducible
description of a running Matrix instance.

A composition can be:

- **Transient** -- assembled by Veltro in response to a need, not saved.
  It exists as long as the Matrix instance is active.

- **Pinned** -- saved by the user (or agent) to the library. It becomes
  a named, reusable configuration that can be loaded by name. Pinning
  is crystallisation: a one-off arrangement becomes infrastructure.

A pinned composition is a text file in a directory. It can be edited by
hand, diffed, version-controlled, and served over 9P to other machines.

### The Library

The library is a directory containing:

- **Module `.dis` files** -- available display and service modules.
- **Pinned composition files** -- saved configurations.

The library is part of the namespace. Veltro can list it, read from it,
write to it. Remote agents can mount it over 9P. The library grows over
time as modules are created and compositions are pinned.

### Crystallisation

When someone (human or agent) arrives at a Matrix composition that is
useful, they pin it. The transient composition becomes a named file in
the library. Next time, it loads in one step.

Over time, the library accumulates operational knowledge: ways of
processing, viewing, and reacting to data that proved valuable. Some
compositions are dashboards. Some are headless servers. Some are
agent-to-agent service bundles. The library does not distinguish. A
composition is a composition.

Veltro can also create new modules. A novel service or visualisation
starts as generated Limbo code, compiled to `.dis`, loaded into Matrix.
If it proves useful, it joins the library. Modules crystallise the same
way compositions do.


## Module Interface

Matrix defines two module interfaces, following the idioms established
by `widget.m` and `Renderer`.

### Display Module

```
MatrixDisplay: module {
    # Initialise with the Draw display, font, and a root path
    # in the namespace that this module reads from.
    init: fn(display: ref Draw->Display,
             font: ref Draw->Font,
             mount: string): string;  # nil=ok, else error

    # Resize the module's drawing area.
    resize: fn(r: Draw->Rect);

    # Update state by re-reading from the mount namespace.
    # Returns 1 if the display needs redrawing, 0 if unchanged.
    update: fn(): int;

    # Draw the current state into the provided image.
    draw: fn(dst: ref Draw->Image);

    # Route a pointer event to the module.
    # Returns 1 if consumed, 0 if not.
    pointer: fn(p: ref Draw->Pointer): int;

    # Route a keyboard event to the module.
    # Returns 1 if consumed, 0 if not.
    key: fn(k: int): int;

    # Reload colours after a theme change.
    retheme: fn(display: ref Draw->Display);

    # Clean up resources. Called before unload.
    shutdown: fn();
};
```

Display modules use `widget.m` components internally. A position table
module might use `Label` for headers, `Scrollbar` for overflow, and
direct `Draw->Image.text()` calls for cell values. The interface
mirrors patterns already present in Lucifer's zone modules.

### Service Module

```
MatrixService: module {
    # Initialise with the mount point this module reads from
    # and a directory path where it writes its outputs.
    init: fn(mount: string, outdir: string): string;  # nil=ok

    # Run the service. Blocks until shutdown.
    # Typically spawned in its own goroutine by the Matrix runtime.
    run: fn();

    # Signal the service to stop. run() should return promptly.
    shutdown: fn();
};
```

A service module's `outdir` is a directory in the Matrix namespace
(e.g., `/n/matrix/modules/signal-watcher/`). The module creates files
there as needed. Other modules, Veltro, or remote agents read them.


## Composition File Format

A composition file is plain text. Each line is one of:

### Layout declarations

```
layout <split> <ratio-left> <ratio-right>
```
Where `<split>` is `hsplit` (left/right) or `vsplit` (top/bottom), and
the ratios are integers representing proportional weights.

Layout lines nest by path prefix:
```
layout hsplit 60 40
left vsplit 70 30
```
This means: split horizontally 60:40, then split the left region
vertically 70:30. Leaf regions are named by their path in the tree:
`left/top`, `left/bottom`, `right`.

Layout declarations are only required when display modules are present.
A headless composition omits them entirely.

### Module assignments (display)

```
<region> <module-name> <mount-path>
```
Assigns a display module to a leaf region. The module name resolves to
a `.dis` file in the library. The mount path is the 9P namespace root
the module reads from.

```
left/top position-table /n/tbl4/portfolio
left/bottom signal-feed /n/tbl4/signals
right risk-gauge /n/tbl4/risk
```

### Service declarations

```
service <module-name> <mount-path>
```
Loads a service module. No region -- it runs in the background.

```
service signal-watcher /n/tbl4/signals
```

### Comments and metadata

Lines starting with `#` are comments. By convention, the first comment
is the composition name:

```
# trading-desk
# pinned 2026-04-04
```

### Maximum layout depth

The layout tree is limited to 4 levels of nesting. This is sufficient
for any practical arrangement (up to ~16 leaf regions) while preventing
pathological compositions.

### Examples

**GUI composition (dashboard):**
```
# tbl4-overview

layout hsplit 60 40
left vsplit 70 30

left/top position-table /n/tbl4/portfolio
left/bottom signal-feed /n/tbl4/signals
right risk-gauge /n/tbl4/risk

service alert-watcher /n/tbl4
```

**Headless composition (server):**
```
# tbl4-monitor

service alert-watcher /n/tbl4
service regime-tracker /n/tbl4/signals
service portfolio-snapshotter /n/tbl4/portfolio
```

**Hybrid composition:**
```
# tbl4-ops

layout vsplit 50 50

top position-table /n/tbl4/portfolio
bottom signal-feed /n/tbl4/signals

service alert-watcher /n/tbl4
service regime-tracker /n/tbl4/signals
```

Same format. Same runtime. The presence or absence of layout lines and
region assignments determines the mode.


## Matrix 9P Namespace

The Matrix runtime exposes its state as a synthetic 9P filesystem. This
is how Veltro and any other tool controls Matrix -- in GUI mode,
headless mode, locally, or remotely.

```
/n/matrix/
    ctl                         # Write commands, read status
    composition                 # Current composition (text, rw)
    modules/
        <name>/
            ctl                 # Module status: running|stopped|error
            type                # display|service
            mount               # Mount path this module reads from
            out/                # Output directory (service modules)
    library/
        modules/
            <name>.dis          # Available module binaries
        compositions/
            <name>              # Pinned composition files
```

### Control commands (write to `/n/matrix/ctl`)

```
load <composition-name>         # Load a pinned composition by name
load -                          # Load composition from /n/matrix/composition
unload                          # Unload all modules, clear layout
pin <name>                      # Save current composition to library
unpin <name>                    # Remove a pinned composition
```

### Composition editing (write to `/n/matrix/composition`)

The current composition is always readable as a text file. Writing a new
composition triggers a reload: the Matrix runtime diffs against the
running state, unloads removed modules, loads added ones, and adjusts
the layout. Veltro's workflow: read the current composition, modify it,
write it back.


## Proof of Concept: TBL4 Trading System

The POC demonstrates the full Matrix loop using the TBL4 trading system
as the data source. It validates both the display and service module
paths and proves that Veltro can assemble and modify compositions
through filesystem operations.

### Prerequisites

- TBL4 running on the Jetson Orin AGX, serving 9P on port 5640.
- InferNode running (same host or remote).
- TBL4's 9P namespace mounted at `/n/tbl4`.

### POC Modules

**Display modules:**

1. **position-table** -- Reads `/n/tbl4/portfolio/positions/`. Scrollable
   table: ticker, quantity, average cost, current value, unrealised P&L,
   portfolio weight. Built with widget.m Scrollbar and direct text
   rendering. Updates by re-reading position files.

2. **signal-feed** -- Reads `/n/tbl4/signals`. Scrollable list of recent
   signals: timestamp, ticker, direction, confidence, agent source.
   Colour-coded by direction (green/red via lucitheme). New signals
   appear at the top.

3. **risk-gauge** -- Reads `/n/tbl4/risk` and `/n/tbl4/portfolio/`.
   Displays: portfolio VaR, expected shortfall, total value, cash,
   defense status, circuit breaker state. Labels and colour-coded
   status indicators.

**Service module:**

4. **alert-watcher** -- Reads `/n/tbl4/signals` and
   `/n/tbl4/portfolio/defense/status`. Writes alert files to its output
   directory when: a high-confidence signal arrives (confidence > 0.7),
   or defense status changes. Veltro reads these alerts.

**Composition:**

```
# tbl4-overview
# Matrix POC

layout hsplit 60 40
left vsplit 70 30

left/top position-table /n/tbl4/portfolio
left/bottom signal-feed /n/tbl4/signals
right risk-gauge /n/tbl4/risk

service alert-watcher /n/tbl4
```

### POC Success Criteria

1. TBL4 9P namespace mounted and readable from InferNode.
2. Matrix loads the composition and enters GUI mode.
3. Three display modules show live data that updates without manual
   refresh.
4. Service module detects a high-confidence signal and writes an alert.
5. Veltro reads `/n/matrix/composition`, modifies it (e.g., changes
   the layout split ratio or swaps a module), writes it back, and the
   Matrix reconfigures live.
6. User pins the composition. Unloads. Reloads by name. Same result.

### What the POC Proves

- The module interfaces are sufficient for real-world tasks.
- The composition file format is expressive enough for practical use.
- Veltro controls Matrix through filesystem operations alone.
- Live 9P data flows through modules to the screen (or to service
  outputs) without custom plumbing.
- The existing widget.m toolkit is adequate for display modules.
- The same composition could run headless by removing the display
  modules and layout lines -- the service module works identically.


## Future: Watch Rules (v1.1)

After the POC validates the static composition model, watch rules add
reactive behaviour directly in the composition file:

```
watch <path>
  <pattern> -> <action>
```

Example:
```
watch /n/tbl4/portfolio/defense/status
  crisis -> load defensive
  normal -> load trading-desk
```

Actions are limited to operations Matrix already supports: `load`,
`unload`, `pin`, `notify`. The watch language is declarative. If a use
case exceeds what watch rules can express, the escape hatch is a service
module written in Limbo that implements arbitrary logic.

Watch rules are deferred from the POC to validate the static model first.


## Future: Marketplace (h402)

InferNode includes a crypto wallet and supports h402 (HTTP 402 Payment
Required) micropayments. This creates the infrastructure for a module
and composition marketplace without building a marketplace platform.

### Mechanism

A module or pinned composition is a file. Files are served over 9P.
9P connections can be gated by payment. Therefore:

- A module author serves `.dis` files from a 9P endpoint with h402
  gating.
- A consumer mounts the remote library. On first access to a paid
  module, h402 triggers payment from the consumer's wallet.
- The module loads into the consumer's Matrix like any local module.
  The network boundary is invisible.

### What Can Be Sold

- **Individual modules** -- specialised display or service modules.
- **Pinned compositions** -- operational layouts and headless server
  configurations that encode domain knowledge. These are the most
  valuable because they represent curated, validated configurations --
  not just code but judgement.
- **Module bundles** -- a set of modules and a composition that work
  together as a product.

### Agent-Generated Assets

Veltro creates modules and compositions as part of its normal operation.
When these are pinned, they become assets. The marketplace enables:

1. Veltro generates a module or composition in response to a need.
2. The user (or agent) validates and pins it.
3. The pinned asset is published (served with h402 gating).
4. Other agents or users mount and pay for it.
5. Revenue flows to the publisher's wallet.

Veltro's operational output has economic value. The agent is not just
a tool -- it is a producer of tradeable intellectual property, curated
by a human or validated by another agent.

### Agent-to-Agent Compositions

In a headless, agent-to-agent scenario, the marketplace operates without
any human involvement:

1. Agent A needs a capability (e.g., a signal processing service).
2. Agent A discovers a published composition via the network.
3. Agent A's Veltro mounts the remote library, pays via h402.
4. The service modules load into Agent A's Matrix.
5. Agent A's own modules read from the service outputs via the namespace.

No GUI. No human. Agents composing, paying for, and consuming each
other's modules through the filesystem. The composition file format,
the module interfaces, and the 9P namespace work identically whether
a human is present or not.

Licensing semantics and payment protocols are deferred to a dedicated
design document.


## Design Decisions

This section records the reasoning behind each major decision so that
future contributors understand not just what was chosen but why.

### Matrix is a module runtime, not an interface system

The GUI is one surface, not the foundation. A composition can be fully
headless -- all service modules, no display, no Lucifer dependency. This
ensures the architecture supports the agent-to-agent future where
compositions are assembled, served, and consumed without any human in
the loop. The display layer is a capability that some modules have, not
a requirement that the system imposes.

### Text file composition format

Plan 9's design principle: text is the universal interface. Text files
can be read, written, edited, diffed, piped, and version-controlled
with standard tools. LLMs generate and manipulate text natively. No
serialisation format, no binary blob, no schema migration. The simplest
thing that works.

### Display and service modules as separate interfaces

A display module draws. A service module computes. Combining them into
one interface would force every module to implement functions it does
not need. Separate interfaces make intent clear. The composition file
distinguishes them syntactically (region assignment vs `service` keyword)
so the runtime knows which interface to expect at load time.

### Modules build on widget.m

InferNode already has a tested, themed widget toolkit. Building a second
one would fragment the ecosystem, create maintenance burden, and produce
visual inconsistency. Matrix display modules are first-class consumers
of widget.m. If a widget is missing, it gets added to widget.m, not to
a Matrix-specific library.

### Layout is a tree of splits

Splits are constrained enough to always produce a usable layout (no
overlapping, no gaps, no z-fighting) and flexible enough for any
practical arrangement. Depth is capped at 4 levels to prevent
pathological nesting. This follows Lucifer's own tiling philosophy.
Layout is only relevant when display modules are present.

### Module namespace isolation

A module sees its mount point and the Matrix control namespace. It does
not inherit the full InferNode namespace. This is structural security:
a module loaded from the network cannot access the user's files, other
mounted services, or the system namespace. The Dis VM enforces the
module interface at load time; the namespace restricts what the module
can reach at runtime.

### Matrix is a 9P server

Everything in InferNode is a file. Matrix exposes its state as a 9P
filesystem so that Veltro, shell scripts, remote agents, and any other
tool can inspect and control it using standard file operations. No
custom IPC, no API client library. `cat /n/matrix/composition` shows
the current state. `echo 'load trading-desk' > /n/matrix/ctl` changes
it. This works identically whether Matrix is running with a GUI or
headless, locally or remotely.

### TBL4 as the POC target

TBL4 is an ideal first target because it already serves a rich 9P
namespace (portfolio, risk, signals, config, audit), the data is live,
the operations map cleanly to module patterns, and it runs on the
Jetson Orin AGX (demonstrating remote mount). Having a real, non-trivial
data source from day one prevents the POC from drifting into abstract
framework-building. The result is immediately useful.

### Marketplace via h402, not a platform

InferNode already has a wallet and h402. The marketplace emerges from
composing existing primitives (9P file serving + payment gating), not
from building a platform. This follows the Plan 9 philosophy: small,
composable mechanisms rather than monolithic services.

### No watch rules in v1

The static composition model must be validated first. If the composition
format, module interface, and Veltro interaction loop work with static
compositions, watch rules are a straightforward addition. If the static
model has problems, watch rules would compound them.
