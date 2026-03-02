# GoDis: A Go-to-Dis Compiler for Inferno's Virtual Machine

GoDis compiles Go source code to Dis bytecode for execution on the Inferno OS
Dis virtual machine. It translates Go's SSA intermediate representation directly
into Dis VM instructions, mapping Go's concurrency primitives, type system, and
memory model onto Dis's runtime facilities.

This document covers the compiler's architecture, the translation strategy, every
critical pattern discovered during development, and every bug encountered and
fixed. It is intended as both a developer reference and a research record.

## Table of Contents

1. [Motivation](#motivation)
2. [Architecture Overview](#architecture-overview)
3. [Build and Test](#build-and-test)
4. [Compilation Pipeline](#compilation-pipeline)
5. [The Dis Virtual Machine](#the-dis-virtual-machine)
6. [Go-to-Dis Translation Strategy](#go-to-dis-translation-strategy)
7. [Frame Layout and Memory Model](#frame-layout-and-memory-model)
8. [Type System Mapping](#type-system-mapping)
9. [Instruction Lowering](#instruction-lowering)
10. [Interface Dispatch](#interface-dispatch)
11. [Closures and Higher-Order Functions](#closures-and-higher-order-functions)
12. [Channels and Concurrency](#channels-and-concurrency)
13. [Exception Handling (panic/recover)](#exception-handling-panicrecover)
14. [Standard Library Interception](#standard-library-interception)
15. [Multi-Package Compilation](#multi-package-compilation)
16. [Critical Patterns](#critical-patterns)
17. [Bug Log](#bug-log)
18. [Test Suite](#test-suite)
19. [Project Statistics](#project-statistics)
20. [Status and Limitations](#status-and-limitations)

---

## Motivation

The Dis VM is the execution engine of Inferno OS, a distributed operating system
descended from Plan 9. Dis is a register-based, garbage-collected virtual machine
with native support for concurrency (channels, spawn), module linking, and
type-safe memory management via pointer maps.

Inferno's native language is Limbo, but Limbo has a small community and limited
tooling. Go shares deep ancestry with Limbo and Inferno through Rob Pike and the
Bell Labs lineage. Both languages have goroutines/channels, garbage collection,
module systems, and similar type philosophies.

GoDis exploits this shared lineage. Rather than writing a Go runtime for Dis, we
map Go primitives directly onto Dis VM features:

| Go Feature | Dis Equivalent |
|---|---|
| `go f()` | `SPAWN` |
| `chan T` | `NEWC` / `SEND` / `RECV` |
| `select` | `ALT` / `NBALT` |
| Garbage collection | Dis reference counting + pointer maps |
| `string` | Dis string type (ADDC, SLICEC, INDC) |
| `[]T` | Dis arrays (NEWA, LENA, INDEXA) |
| `map[K]V` | Limbo-compatible ADT (future: native Dis) |
| `panic/recover` | Dis exception handler tables (RAISE) |
| Module imports | Dis LDT (Loader Dispatch Table) |

This "adapt to the runtime" strategy means compiled Go programs are first-class
Dis citizens: they can be spawned by Limbo programs, share channels across
language boundaries, and participate in Inferno's namespace and security model.

---

## Architecture Overview

```
tools/godis/
├── compiler/                  # Core compiler (12,237 lines)
│   ├── compiler.go            #   Orchestrator: parse, SSA, link, emit (1,748 lines)
│   ├── lower.go               #   SSA → Dis instruction lowering (7,019 lines)
│   ├── types.go               #   Go → Dis type mapping
│   ├── frame.go               #   Stack frame slot allocator
│   ├── builtins.go            #   Sys module function signatures
│   └── compiler_test.go       #   E2E test suite (3,056 lines)
├── dis/                       # Dis bytecode library (1,994 lines)
│   ├── opcode.go              #   62+ VM opcode definitions
│   ├── inst.go                #   Instruction representation
│   ├── encode.go              #   Binary serialization
│   ├── decode.go              #   Binary deserialization
│   ├── module.go              #   Module structure
│   ├── data.go                #   Data section (strings, constants)
│   ├── typedesc.go            #   Type descriptor format
│   └── dis_test.go            #   Round-trip tests
├── cmd/
│   ├── godis/main.go          #   CLI compiler tool
│   ├── debug/main.go          #   Dis bytecode inspector
│   └── ssadump/main.go        #   SSA IR dump tool
└── testdata/                  # 172 test programs
    ├── hello.go ... switch.go #   Single-file feature tests
    ├── tier6_*.go             #   Coverage tier tests
    ├── bench/                 #   Performance benchmarks
    ├── chain/                 #   Multi-package import chain
    ├── multipkg/              #   Multi-package tests
    └── sharedtype/            #   Cross-package type sharing
```

**Dependencies:** Go 1.24+, `golang.org/x/tools` (SSA construction).

---

## Build and Test

```sh
cd tools/godis

# Build everything
go build ./...

# Run all tests
go test ./... -count=1

# Compile a Go program to Dis
go run ./cmd/godis/ testdata/hello.go

# Run the compiled program on Inferno's emulator
# (from the infernode project root)
./emu/Linux/o.emu -r. /tools/godis/hello.dis

# Inspect compiled bytecode
go run ./cmd/debug/ hello.dis

# Dump SSA IR for a Go file
go run ./cmd/ssadump/ testdata/hello.go
```

---

## Compilation Pipeline

```
 Go source files (.go)
        │
        ▼
 ┌──────────────────┐
 │  go/parser        │  Parse to AST
 │  go/types         │  Type-check
 └────────┬─────────┘
          │
          ▼
 ┌──────────────────┐
 │  x/tools/go/ssa   │  Build SSA IR
 │  ssautil.Packages │  (with optimizations)
 └────────┬─────────┘
          │
          ▼
 ┌──────────────────┐
 │  Compiler         │
 │  ├─ scanClosures  │  Discover closures, method values
 │  ├─ collectTypes  │  Build type tag registry
 │  ├─ collectMethods│  Map interface dispatch tables
 │  └─ collectInits  │  Find init() functions
 └────────┬─────────┘
          │
          ▼
 ┌──────────────────┐
 │  funcLowerer      │  Per-function lowering:
 │  ├─ allocateSlots │    Frame layout for params, locals
 │  ├─ lowerBlock    │    SSA block → instruction sequence
 │  ├─ patchBranches │    Resolve forward references
 │  └─ emitHandler   │    Exception tables (if recover)
 └────────┬─────────┘
          │
          ▼
 ┌──────────────────┐
 │  ModuleData       │  Assemble: instructions, type
 │  ├─ TypeDescs     │  descriptors, data section,
 │  ├─ Links/LDT    │  module links, handler tables
 │  └─ Encode()     │  Serialize to binary .dis
 └──────────────────┘
```

### Phase Details

**1. Parsing and Type Checking.** Standard Go toolchain. We use
`go/parser.ParseFile` and `go/types.Config.Check`. A custom `stubImporter`
provides synthetic type information for packages that don't exist in the host Go
environment but have Dis equivalents (`inferno/sys`, `fmt`, `strings`, `math`,
`strconv`, `errors`, `os`, `sort`, `sync`, `time`, `log`, `io`).

**2. SSA Construction.** `golang.org/x/tools/go/ssa` builds the SSA form with
`ssa.InstantiateGenerics | ssa.SanityCheckFunctions`. Every Go function becomes a
sequence of `ssa.BasicBlock`s containing typed SSA instructions. This is our
primary IR — we never build our own.

**3. Pre-compilation Analysis.** Before lowering any function, the compiler scans
all SSA functions to:
- Discover closures (`MakeClosure` → inner function mapping)
- Discover bound method wrappers (`$bound` functions synthesized by SSA)
- Allocate type tags for interface dispatch
- Build method dispatch tables (`ifaceDispatch`)
- Collect `init#N` functions for startup sequencing

**4. Per-function Lowering.** Each SSA function is lowered independently by a
`funcLowerer`. Frame slots are allocated for parameters, locals, and temporaries.
SSA instructions are translated to Dis instructions one basic block at a time.
Branch targets are recorded as patches and resolved after all blocks are emitted.

**5. Module Assembly.** All lowered functions are concatenated into a single
instruction stream (Dis modules are flat). Type descriptors, the data section
(string/float literals, globals), module links (Sys imports), and exception
handler tables are assembled into a `ModuleData` and serialized to binary.

---

## The Dis Virtual Machine

Dis is a register-based VM with the following characteristics:

- **Three-operand instructions:** `OP src, mid, dst` where `dst = mid OP src`
  for arithmetic. Note the operand order — this is opposite to most architectures.
- **Memory spaces:** FP (frame pointer, local variables), MP (module data,
  globals/constants), immediate.
- **Typed instructions:** Separate opcodes for words (W), big integers (L),
  floats (F), pointers (P), bytes (B), strings (C).
- **Reference counting GC:** Pointer assignments (`MOVP`) automatically adjust
  reference counts. Type descriptors contain pointer maps so the VM knows which
  frame slots and heap objects contain pointers.
- **H = nil:** The constant `H` (`(void*)(-1)`, 0xFFFFFFFFFFFFFFFF on 64-bit)
  represents nil/uninitialized for all pointer types.
- **Concurrency primitives:** `SPAWN` (create thread), `NEWC` (create channel),
  `SEND`/`RECV` (synchronous channel ops), `ALT`/`NBALT` (select).
- **Exception handling:** Handler tables map PC ranges to exception handlers.
  `RAISE` throws a string exception.
- **Module linking:** The Loader Dispatch Table (LDT) enables calling functions
  in other modules (e.g., the Sys built-in module).

---

## Go-to-Dis Translation Strategy

The core insight is **"adapt Go to Dis runtime"** — rather than implementing Go's
runtime semantics on top of Dis, we identify the closest Dis primitive for each
Go feature and generate code that uses it natively.

### What Maps Directly

- **Goroutines → SPAWN.** Go's `go f(args)` compiles to `SPAWN` with a new
  frame. The Dis VM handles scheduling.
- **Channels → NEWC/SEND/RECV.** Go channels map directly to Dis channels.
  Buffered channels use NEWC's buffer size operand.
- **Strings → Dis strings.** Go strings are Dis strings. Concatenation is ADDC,
  slicing is SLICEC, indexing is INDC.
- **Slices → Dis arrays.** Go slices compile to Dis arrays created with NEWA.
  Length is LENA, indexing is INDW/INDB.
- **Select → ALT/NBALT.** Go's select statement compiles to Dis's ALT (blocking)
  or NBALT (non-blocking with default).
- **Panic → RAISE.** Go's panic compiles to Dis RAISE with a string exception.
- **Module imports → LDT.** Calls to `inferno/sys` functions use Dis's module
  linking via IMFRAME/IMCALL with LDT indices.

### What Requires Synthesis

- **Interfaces** — Dis has no native interfaces. We implement tagged dispatch
  using two-word values (type tag + data) and BEQW dispatch chains.
- **Maps** — Dis has no native hash maps. We use wrapper structs with sorted
  arrays and binary search (future: native Dis table type).
- **Closures** — Dis has no closures. We allocate heap structs containing free
  variables and a function tag, with dispatch chains at call sites.
- **Defer** — Dis has no defer. We inline deferred calls at every return point
  in LIFO order, with exception handlers for panic paths.
- **Recover** — Dis exception handlers + a module-data bridge pattern (handler
  writes exception to global, deferred closure reads it).
- **Standard library** — Intercepted and inlined. `fmt.Sprintf` becomes a
  sequence of CVTWC/ADDC operations. `strings.Contains` becomes a SLICEC loop.

---

## Frame Layout and Memory Model

Every Dis function call allocates a frame. GoDis uses a fixed header followed by
locals and temporaries:

```
Offset   Slot          Purpose
──────   ────          ───────
0        REGLINK       Return address (managed by VM)
8        REGFRAME      Caller's frame pointer
16       REGMOD        Module pointer
24       REGTYP        Type descriptor pointer
32       REGRET        Return value pointer
40       STemp         Scratch temporary (word)
48       RTemp         Scratch temporary (real/float)
56       DTemp         Scratch temporary (word)
64+      Locals        Parameters, variables, temporaries
```

**MaxTemp = 64 bytes.** Arguments to called functions start at offset 64 in the
callee's frame.

### Slot Allocation

The `Frame` struct tracks slot allocation with a pointer bitmap:

- `AllocWord(name)` — 8-byte non-pointer slot. Used for integers, booleans,
  floats, and addresses computed by LEA.
- `AllocPointer(name)` — 8-byte pointer slot. GC-traced. Used for strings,
  arrays, channels, heap objects.
- `AllocReal(name)` — 8-byte float slot. Used for float64 data items in MP.
- `AllocTemp(isPtr)` — Unnamed temporary.
- `allocPtrTemp()` — Pointer temp with H-initialization (emits `MOVW $(-1)`).

### Type Descriptors

Every frame and heap object has a type descriptor that tells the GC which offsets
contain pointers. The descriptor encodes:

- `size` — total size in bytes
- `map` — bitmap where 1 = pointer at that word offset

This is critical for correctness. If a pointer slot is not marked in the type
descriptor, the GC won't trace it and the object may be prematurely freed. If a
non-pointer slot is marked as a pointer, the GC will try to adjust a reference
count on garbage data, causing crashes.

### The H Constant

Dis represents nil as `H = (void*)(-1) = 0xFFFFFFFFFFFFFFFF`. This is NOT zero.
Every pointer slot in a new frame or heap object is initialized to H by the VM
(if the type descriptor marks it as a pointer). Non-pointer slots are NOT
initialized — they contain whatever was previously on the stack.

This asymmetry is a persistent source of bugs. See [Bug Log](#bug-log).

---

## Type System Mapping

```go
type DisType struct {
    Size  int32  // Bytes needed
    IsPtr bool   // GC-tracked pointer?
}
```

| Go Type | Dis Size | IsPtr | Notes |
|---|---|---|---|
| `int`, `int64`, `uint64` | 8 | No | WORD (64-bit on Dis) |
| `int32`, `int16`, `int8` | 8 | No | Widened to WORD |
| `bool` | 8 | No | WORD (0 or 1) |
| `float64` | 8 | No | Dis REAL |
| `string` | 8 | Yes | Dis string (ref-counted) |
| `*T` (pointer) | 8 | Yes | Heap pointer |
| `[]T` (slice) | 8 | Yes | Dis array |
| `map[K]V` | 8 | Yes | Wrapper struct pointer |
| `chan T` | 8 | Yes | Wrapper struct pointer |
| `func(...)` | 8 | Yes | Closure struct pointer |
| `interface{}` | 16 | No | 2 WORDs: [tag, value] |
| `struct{...}` | N*8 | Mixed | Consecutive slots per field |
| `error` | 16 | No | Interface (2 WORDs) |

### Interface Representation

Interfaces are two consecutive WORDs, not a pointer:

```
Offset 0: type tag (WORD) — integer identifying the concrete type
Offset 8: value (WORD)   — the concrete value or pointer to heap data
```

The type tag is allocated by `AllocTypeTag(typeName)` and is unique per concrete
type. Tag 0 means nil interface. The value word holds the concrete value directly
for scalar types, or a pointer to heap-allocated data for structs.

### WORD = LONG = 8 bytes

On ARM64 Dis, both `int` (WORD) and `big` (LONG) are 64-bit. The CVTWL/CVTLW
instructions are just copies, NOT 32-bit truncation operations. This is a
difference from 32-bit Dis where WORD=4, LONG=8.

---

## Instruction Lowering

The `funcLowerer` translates each SSA instruction to one or more Dis instructions.
The lowering is implemented as a large switch on SSA instruction type in
`lower.go` (6,703 lines).

### Operand Encoding

Dis instructions have three operand slots: src, mid, dst. Each can be:

- `Imm(v)` — immediate constant
- `FP(off)` — frame pointer + offset (locals)
- `MP(off)` — module pointer + offset (globals, constants)
- `FPInd(base, off)` — indirect through FP (heap object fields)
- `MPInd(base, off)` — indirect through MP

**Critical:** `Operand{Mode: 0}` is AMP (absolute MP), NOT "no operand". The
"no operand" mode is AXXX=3. Always use the `Inst0()`, `Inst1()`, `Inst2()`
helpers to construct instructions with the correct number of operands.

### Three-Operand Semantics

For arithmetic: `OP src, mid, dst` means `dst = mid OP src`.

This is the **opposite** of what you might expect. For `a - b`:
```
SUBW  b, a, result    # result = a - b  (dst = mid - src)
```

For non-commutative operations (SUB, DIV, MOD), the operands must be swapped
from the natural Go order. The compiler's `emitArith` handles this.

### Branch Semantics

For conditional branches: `BOP src, mid, dst` means "if src OP mid, goto dst".

```
BLTW  x, y, target    # if x < y, goto target
BGEW  i, len, done    # if i >= len, goto done
```

The **first operand is the tested value**. This is a frequent source of bugs —
swapping `BGEW FP(i), FP(len), done` to `BGEW FP(len), FP(i), done` silently
inverts the condition.

### Comparison Operand Order

For Dis comparison instructions used by the JIT:
`CMP src, mid` tests `src OP mid`. The CMP operand order must match the branch
condition. Getting this backwards silently inverts all comparisons.

---

## Interface Dispatch

### Overview

Go interfaces are implemented as tagged two-word values with dispatch chains.
This avoids virtual method tables (which Dis doesn't support) in favor of
inline type-tag switching.

### Type Tag Registry

```go
type Compiler struct {
    typeTagMap  map[string]int32  // "main.Dog" → 1, "main.Cat" → 2
    typeTagNext int32             // next available tag
}
```

Tags are allocated during pre-compilation analysis when concrete types are
discovered implementing interface methods.

### MakeInterface

```go
var a Animal = Dog{name: "Rex"}
```

Compiles to:
```
MOVW  $tag_Dog, FP(iface+0)     # store type tag
MOVW  FP(dog_val), FP(iface+8)  # store value (or LEA for structs)
```

### TypeAssert

```go
d, ok := a.(Dog)
```

Compiles to:
```
BEQW  $tag_Dog, FP(iface+0), $match   # check tag
MOVW  $0, FP(ok)                       # mismatch: ok = false
JMP   $end
match:
MOVW  FP(iface+8), FP(d)              # extract value
MOVW  $1, FP(ok)                       # ok = true
end:
```

Without comma-ok, a mismatch raises a panic instead.

### Interface Method Calls (Invoke)

For a single implementing type, the call is direct. For multiple types:

```go
a.Speak()  // a is Animal, could be Dog or Cat
```

Compiles to a BEQW dispatch chain:
```
BEQW  $tag_Dog, FP(iface+0), $call_dog
BEQW  $tag_Cat, FP(iface+0), $call_cat
RAISE "unknown type"

call_dog:
  IFRAME ...
  # load receiver from iface+8
  ICALL dog_speak
  JMP $exit

call_cat:
  IFRAME ...
  # load receiver from iface+8
  ICALL cat_speak
  JMP $exit

exit:
```

### Type Switches

Type switches compile to sequential tag comparisons, same as multi-type assert.

### Error Interface

The `error` interface gets special treatment. `errors.New("msg")` creates a
tagged interface with tag=errorString and value=the string itself (not a pointer
to a struct). The `Error()` method is synthetic — it just returns the value word
directly, since the value IS the error string.

---

## Closures and Higher-Order Functions

### Closure Structs

Dis has no native closure support. GoDis allocates heap structs for closures:

```
Offset 0: function tag (WORD)   — identifies which function this closure calls
Offset 8: free var 0            — captured variable
Offset 16: free var 1           — captured variable
...
```

The function tag is critical for dynamic dispatch — when a closure is passed as a
value and called through a variable, the tag identifies which function to call.

### MakeClosure

```go
adder := func(x int) int { return x + base }
```

Compiles to:
```
INEW  $closure_td          # allocate closure struct
MOVW  $tag_anon1, FPInd(closure, 0)  # store function tag
MOVW  FP(base), FPInd(closure, 8)    # capture 'base'
```

### Dynamic Dispatch

When calling a closure through a variable (higher-order function):

```go
func apply(f func(int) int, x int) int { return f(x) }
```

The compiler emits a BEQW chain over all closures with matching signatures:
```
MOVW  FPInd(f, 0), FP(tag)          # read function tag
BEQW  $tag_anon1, FP(tag), $call1   # is it closure 1?
BEQW  $tag_anon2, FP(tag), $call2   # is it closure 2?
RAISE "unknown function"

call1:
  IFRAME $frame_anon1
  MOVP  FP(f), MaxTemp+0(fp)        # pass closure ptr (for free vars)
  MOVW  FP(x), MaxTemp+8(fp)        # pass argument
  ICALL anon1
  JMP $exit
...
```

### Signature Matching

`closureSignaturesMatch()` compares Go-level signatures (parameter types, return
types) to determine which closures could be called through a given variable. The
comparison uses Go's `types.Signature` and excludes hidden parameters.

### Plain Functions as Values

When a named function (not a closure) is used as a value:
```go
f := myFunc
```

`materializeFuncValue()` wraps it in a tag-only 8-byte closure struct (no free
variables, just the tag). This ensures all function values have the same
representation at call sites.

### Method Values / Bound Wrappers

```go
a := Adder{base: 10}
f := a.Add  // method value
```

Go SSA synthesizes `(*Adder).Add$bound` — a wrapper that captures the receiver.
These `$bound` functions are not regular package members or anonymous functions.
After `scanClosures`, we iterate the closure map to discover them and add them to
the compilation set.

---

## Channels and Concurrency

### Channel Wrapper Pattern

Every `chan T` is a heap-allocated wrapper struct:

```
Offset 0:  rawCh   (PTR)  — the actual Dis channel
Offset 8:  closed  (WORD) — 0 = open, 1 = closed
Offset 16: cap     (WORD) — buffer capacity
```

Type descriptor: 24 bytes, pointer at offset 0.

This wrapper is necessary because Dis channels have no native close semantics.
The `closed` flag is checked on send (panic if closed) and on receive (drain
buffer then return zero value).

### Operations

| Go | Dis |
|---|---|
| `make(chan T)` | `NEWC` + `INEW` wrapper |
| `make(chan T, n)` | `NEWC` with buffer size in mid operand |
| `ch <- v` | Check closed flag, then `SEND` |
| `<-ch` | If open: `RECV`. If closed: `NBALT` to drain, zero if empty |
| `v, ok := <-ch` | Same as above but set ok=false when closed+empty |
| `close(ch)` | `MOVW $1` to closed flag at wrapper offset 8 |
| `cap(ch)` | Read wrapper offset 16 |
| `for range ch` | CommaOk receive, exit when ok=false |

### Select

Go's `select` compiles to Dis `ALT` (blocking, no default) or `NBALT`
(non-blocking, has default). The ALT instruction takes a descriptor encoding
which channels to wait on and which direction (send/receive).

### Known Limitation

Goroutines blocked on `RECV` when `close()` is called on another goroutine will
NOT be unblocked. This is a Dis VM limitation — the VM's channel implementation
has no close-notification mechanism. The `closed` flag is only checked at the
next receive attempt.

---

## Exception Handling (panic/recover)

### Panic

`panic(v)` compiles to:
```
# Convert v to string if needed (CVTWC for int, etc.)
RAISE FP(str)    # or RAISE MP(str) for string constants
```

### Recover and Exception Handler Tables

`recover()` uses Dis exception handler tables. The mechanism is complex because
Go's recover only works inside deferred functions, which are closures.

**The module-data bridge pattern:**

1. The enclosing function has a Dis exception handler table entry covering its
   body. When an exception occurs, the VM jumps to the handler PC.
2. The handler stores the exception string to a global MP slot (`excGlobal`).
3. The handler then executes deferred closures.
4. Inside a deferred closure, `recover()` reads from `excGlobal(mp)`.
5. If non-nil, recover returns the value as a tagged interface
   (tag=errorString, value=the exception string) and zeros the global.

**Handler table entry format:**
```
{eoff, pc1, pc2, descID=-1, ne=0, wildPC}
```
- `eoff` — offset in frame where VM stores exception string
- `pc1, pc2` — PC range covered by handler
- `descID=-1` — no type descriptor (exception is a string)
- `ne=0` — number of named exceptions (0 = wildcard only)
- `wildPC` — PC to jump to on any exception

**Zero-divide check:** ARM64's `sdiv` returns 0 on divide-by-zero (no trap).
The compiler emits an explicit check before every integer DIVW/MODW:
```
BNEW  divisor, $0, $skip
RAISE "zero divide"
skip:
DIVW  ...
```

---

## Standard Library Interception

GoDis does not link Go's standard library. Instead, it intercepts calls to known
packages and inlines equivalent Dis instruction sequences.

### fmt Package

| Go Function | Implementation |
|---|---|
| `fmt.Sprintf(fmt, args...)` | Parse format string at compile time, emit inline ops per verb |
| `fmt.Printf(fmt, args...)` | Sprintf + sys.print |
| `fmt.Println(args...)` | Trace varargs, emit print per element with spaces + newline |
| `fmt.Errorf(fmt, args...)` | Sprintf + wrap as tagged error interface |

**Sprintf verb implementation:**
- `%d`, `%v` (int) → CVTWC (integer to decimal string)
- `%s` → pass-through
- `%c` → INSC (rune to single-character string)
- `%x` → hex loop (ANDW + SHRW + lookup table)
- `%f`, `%g` → CVTFC (float to string)
- `%t` → branch on bool, emit "true"/"false"
- `%q` → ADDC with quote characters
- `%p` → CVTWC with "0x" prefix
- `%b` → binary loop (ANDW + SHRW)
- `%o` → octal loop
- `%%` → literal "%"
- Width/precision padding → LENC + ADDC loop

Multiple format segments are concatenated with ADDC (string concatenation).

**Vararg tracing:** `fmt.Println` and `fmt.Sprintf` receive arguments as
`[]interface{}`. The compiler traces the SSA data flow backwards:
Slice → Alloc → IndexAddr → Store → MakeInterface → original value.
This recovers the original typed values so we can emit type-specific print code.

### strings Package

| Function | Implementation |
|---|---|
| `strings.Contains(s, sub)` | SLICEC + BEQC loop |
| `strings.HasPrefix(s, pre)` | SLICEC + BEQC |
| `strings.HasSuffix(s, suf)` | LENC + SLICEC + BEQC |
| `strings.Index(s, sub)` | SLICEC scan loop |
| `strings.TrimSpace(s)` | INDC loop from both ends, check whitespace, SLICEC |
| `strings.Split(s, sep)` | Two-pass: count occurrences, NEWA, fill with SLICEC |
| `strings.Join(elems, sep)` | Loop: INDW element, MOVP deref, ADDC with sep |
| `strings.Replace(s, old, new, n)` | Scan + SLICEC + ADDC rebuild |
| `strings.ToUpper(s)` / `ToLower(s)` | INDC loop, INSC rebuild with ±32 |
| `strings.Repeat(s, n)` | ADDC loop |

### math Package

| Function | Implementation |
|---|---|
| `math.Abs(x)` | MOVF + BGEF + NEGF (conditional negation) |
| `math.Sqrt(x)` | Newton's method: 15 iterations, unrolled |
| `math.Min(x, y)` | MOVF + BLTF branch |
| `math.Max(x, y)` | MOVF + BGTF branch |

### strconv Package

| Function | Implementation |
|---|---|
| `strconv.Itoa(i)` | CVTWC |
| `strconv.Atoi(s)` | CVTCW (with error interface return) |
| `strconv.FormatInt(i, base)` | CVTWC (base 10), loop for base 2/8/16 |

### Other Packages

| Package | Functions | Implementation |
|---|---|---|
| `errors` | `New(msg)` | Tagged interface: tag=errorString, value=string |
| `os` | `Exit(code)` | RET |
| `sort` | `Ints`, `Strings`, `IntsAreSorted` | Inline insertion sort |
| `sync` | `Mutex`, `WaitGroup`, `Once` | Channel-based stubs |
| `time` | `After`, `Duration.Milliseconds`, `Time.Sub` | sys.sleep wrapper |
| `log` | `Println`, `Fatal` | sys.print + optional exit |
| `io` | `Reader`, `Writer`, `EOF` | Type stubs |

### Sys Module (inferno/sys)

Direct Dis module calls via LDT:

| Function | Dis Call | Notes |
|---|---|---|
| `sys.fildes(n)` | IMFRAME + IMCALL | Returns file descriptor |
| `sys.fprint(fd, fmt, args...)` | IFRAME + IMCALL | Variadic (custom TD) |
| `sys.print(fmt, args...)` | IFRAME + IMCALL | Variadic |
| `sys.sleep(ms)` | IMFRAME + IMCALL | |
| `sys.millisec()` | IMFRAME + IMCALL | Returns int |
| `sys.open(path, mode)` | IMFRAME + IMCALL | Returns FD |
| `sys.read(fd, buf, n)` | IMFRAME + IMCALL | Returns count |
| `sys.write(fd, buf, n)` | IMFRAME + IMCALL | Returns count |
| `sys.create(path, mode, perm)` | IMFRAME + IMCALL | Returns FD |
| `sys.seek(fd, off, whence)` | IMFRAME + IMCALL | |
| `sys.bind(src, dst, flags)` | IMFRAME + IMCALL | Namespace binding |
| `sys.chdir(path)` | IMFRAME + IMCALL | |
| `sys.remove(path)` | IMFRAME + IMCALL | |
| `sys.pipe(fds)` | IMFRAME + IMCALL | |
| `sys.dup(old, new)` | IMFRAME + IMCALL | |
| `sys.pctl(flags, movefd)` | IMFRAME + IMCALL | Process control |

---

## Multi-Package Compilation

### Local Package Imports

```go
import "mathutil"  // resolved from baseDir/mathutil/*.go
```

The `localImporter` falls through from `stubImporter`. It reads all `.go` files
in `baseDir/pkg/`, parses them, and provides type information. All packages are
inlined into a single `.dis` file — there is no Dis inter-module linking for
local packages.

### Cross-Package Name Resolution

Global variables from imported packages are prefixed with the package path to
avoid collisions:
```
main.counter    → MP offset 0
mathutil.counter → MP offset 8
```

### Recursive Imports

Local packages can import other local packages. The `localImporter` resolves
transitively: if `main` imports `mid` and `mid` imports `base`, all three are
compiled and inlined.

### Shared Types

Cross-package struct creation and return works correctly. A struct defined in
package `geom` can be created in `main` and the fields are laid out consistently
because both packages see the same `types.Struct` from the type checker.

---

## Critical Patterns

These patterns were discovered through debugging and are essential for correct
code generation. Each represents a class of bug that is easy to reintroduce.

### 1. Operand Zero-Value Is AMP, Not "No Operand"

```go
// WRONG — Mode 0 is AMP (absolute MP addressing)
inst := dis.Inst{Op: "MOVW", Dst: operand}

// RIGHT — use helpers that set unused operands to AXXX
inst := dis.Inst1("MOVW", dst)
```

`Operand{Mode: 0}` encodes as AMP (address mode 0), which means "absolute
address in module data." Using a zero-value operand when you mean "no operand"
will cause the VM to read from a garbage MP address.

### 2. LEA Results Are NOT GC Pointers

When computing an address with LEA (Load Effective Address), the result is a raw
address into the stack or module data. It is NOT a heap pointer. Storing it in a
pointer-typed slot will confuse the GC.

```go
// Stack addresses, MP addresses, FieldAddr, IndexAddr results:
slot := frame.AllocWord(name)  // NOT AllocPointer
```

Interior pointers (field addresses, array element addresses) are also non-GC
words.

### 3. Phi Elimination: MOVs at End of Predecessors

SSA phi nodes are eliminated by inserting MOV instructions at the end of each
predecessor block (before the terminator). If multiple phis exist, their moves
must not interfere — the compiler handles this by emitting all moves before any
branch.

### 4. allocPtrTemp Is Unsafe in Loops

`allocPtrTemp()` emits a `MOVW $(-1)` (H-initialization) at the current
compilation point. If used inside a loop body, the MOVW runs every iteration,
stomping valid pointer values without calling destroy — causing reference count
leaks.

**Fix:** For loop-body pointer temporaries where the underlying data is kept
alive by another reference, use `AllocWord` + `MOVW` instead (no refcount
management).

### 5. SLICEC Operand Order

```
SLICEC src, mid, dst  →  dst = dst[src:mid]
```

Where src=start index, mid=end index. The destination string is ALSO the input
string — SLICEC modifies in place (well, replaces the string reference).

### 6. INDW vs INDC

- **INDW** is for array element addressing: `INDW arr, addr, idx` → addr = &arr[idx]
- **INDC** is for string character extraction: `INDC str, idx, dst` → dst = rune at str[idx]

Using INDW on a string causes a nil dereference because a string is not an array
object.

### 7. INDW Operand Order for Arrays

```
INDW src=array, mid=resultAddr, dst=index
```

The mid operand gets the address, NOT dst. This is counterintuitive given that
most instructions put results in dst.

### 8. Variadic Functions Need IFRAME, Not IMFRAME

Functions with frame size 0 (like `print`, `fprint`) are variadic in Dis. They
require `IFRAME` with a custom call-site type descriptor, not `IMFRAME` with the
standard function TD.

### 9. Nil Interface Must Be Explicitly Zeroed

When materializing a nil interface constant, both words must be explicitly set
to 0:
```
MOVW $0, FP(iface+0)   # tag = 0
MOVW $0, FP(iface+8)   # value = 0
```

Non-pointer frame slots are NOT zero-initialized by the VM, so relying on
default values will read garbage.

### 10. constOperand Nil: H for Pointers, 0 for Scalars

```go
func constOperand(c *ssa.Const) Operand {
    if c.Value == nil {
        if isPointerType(c.Type()) {
            return Imm(-1)  // H (nil pointer)
        }
        return Imm(0)       // zero value
    }
}
```

Pointer nil is H (-1), not 0. Getting this wrong breaks nil comparisons for
slices, maps, channels, and function values.

### 11. Nil Slice/Map Safety

`LENA` on a nil (H) array crashes the VM. Before computing `len(s)` or
`cap(s)`, check for nil:

```
MOVW  $0, FP(dst)              # default: length = 0
BEQW  FP(slice), $(-1), $skip  # if slice == H, skip
LENA  FP(slice), FP(dst)       # safe: slice is non-nil
skip:
```

Same pattern for `append(nil, ...)`.

### 12. println(bool) Must Print "true"/"false"

Go's `println(true)` prints the string "true", not "1". The compiler emits:
```
MOVP  MP("false"), FP(tmp)
BEQW  FP(val), $0, $skip
MOVP  MP("true"), FP(tmp)
skip:
# print FP(tmp)
```

### 13. Branch Operand Order

`BGEW src, mid, dst` means "if src >= mid goto dst". The first operand is
always the tested value. Swapping operands silently inverts the condition.

---

## Bug Log

Every bug encountered during development, in chronological order. Each entry
describes the symptom, root cause, and fix.

### B01: Operand Zero-Value Encodes as AMP

**Symptom:** Random crashes when instructions had fewer than 3 operands.
**Cause:** Default `Operand{}` has `Mode=0`, which is AMP (absolute MP), not
"no operand" (AXXX=3).
**Fix:** `Inst0()`, `Inst1()`, `Inst2()` helpers that set unused operands to
AXXX mode.

### B02: SUB/DIV/MOD Operand Swap

**Symptom:** `a - b` computed `b - a`.
**Cause:** Dis three-operand format is `dst = mid OP src`, so SUB requires
swapping the Go-order operands.
**Fix:** `emitArith` swaps operands for non-commutative ops.

### B03: Frame Pointer Slots for LEA Results

**Symptom:** GC corruption after FieldAddr/IndexAddr operations.
**Cause:** LEA results (stack/MP addresses) stored in pointer-typed slots.
The GC tried to trace them as heap pointers.
**Fix:** All LEA destinations use `AllocWord`.

### B04: Phi MOVs Clobbering Each Other

**Symptom:** Wrong values after if/else branches with multiple phi nodes.
**Cause:** Phi elimination MOVs were inserted inline, so later MOVs could
read values already overwritten by earlier MOVs.
**Fix:** Emit all MOVs at end of predecessor blocks, using temps for conflicts.

### B05: MOVP for Pointer ChangeType

**Symptom:** `alloc:D2B: addr in free blk` — heap corruption during cleanup.
**Cause:** `lowerChangeType` used MOVW for ALL types, including pointers
(channels, slices). This bypassed reference counting.
**Fix:** Use MOVP for pointer types to maintain GC reference counts.

### B06: Closure Free Var Offset Off-by-8

**Symptom:** Closures read wrong captured values.
**Cause:** Free variable loads started at offset 0 of the closure struct,
overlapping the function tag.
**Fix:** `emitFreeVarLoads()` starts at offset 8 (skip tag word).

### B07: Bound Method Wrappers Not Compiled

**Symptom:** "unknown function" panic when calling method values.
**Cause:** `$bound` wrapper functions synthesized by SSA are not package
members or anonymous functions — they weren't discovered.
**Fix:** After `scanClosures`, iterate `closureMap` to find unseen inner
functions and add to compilation set.

### B08: INDC vs INDW for String Indexing

**Symptom:** Nil dereference in `emitStringToRuneSlice`.
**Cause:** Used INDW (array element addr) on a string. Strings are not arrays.
Also had wrong operand order.
**Fix:** Use `INDC src, FP(idx), FP(runeSlot)`.

### B09: Nil Pointer Returns 0 Instead of H

**Symptom:** `*Node == nil` comparisons always false for BST/linked list code.
**Cause:** `constOperand(nil:*T)` returned `Imm(0)`. Dis nil is H = -1.
**Fix:** Return `Imm(-1)` for pointer types.

### B10: MakeSlice Zero-Initialization

**Symptom:** `make([]int, n)` contained garbage values.
**Cause:** `NEWA`'s `initarray` skips types with `np==0` (no pointers),
leaving non-pointer elements uninitialized.
**Fix:** Emit explicit zero-init loops (`emitArrayZeroInit` /
`emitArrayZeroInitDynamic`) after NEWA.

### B11: Nil Slice len() Crash

**Symptom:** VM crash on `len(nil_slice)`.
**Cause:** `LENA` on H (nil) dereferences invalid memory.
**Fix:** Emit nil check before LENA. Constant nil → emit `MOVW $0` directly.

### B12: allocPtrTemp in Loops Leaks References

**Symptom:** Memory growth in long-running programs with loops.
**Cause:** `allocPtrTemp()` emits H-init MOVW at compilation point. In loops,
this stomps valid pointers without destroy → refcount never decremented.
**Fix:** Use `AllocWord` + manual MOVW for loop-body temps where data is kept
alive by other references.

### B13: Nil Interface Not Explicitly Zeroed

**Symptom:** Type assertions on nil interfaces matched random types.
**Cause:** Non-pointer frame slots contain stack garbage. Nil interface
materialization didn't zero the tag word.
**Fix:** Explicit `MOVW $0` for both tag and value words.

### B14: Struct Return By Value — Only First Field Copied

**Symptom:** Multi-field struct returns had garbage in fields after the first.
**Cause:** `lowerReturn` only copied one word to REGRET for struct types.
**Fix:** Copy ALL struct fields to REGRET offsets. Also fixed `slotOf` to
call `allocStructFields()` for struct-typed SSA values.

### B15: Cross-Package Global Name Collision

**Symptom:** Wrong values for globals when two packages had same-named vars.
**Cause:** Globals from all packages shared the same namespace.
**Fix:** Prefix with package path: `pkgPath.varName`.

### B16: Unsigned Comparison Wrong for uint64

**Symptom:** `uint64(a) < uint64(b)` gave wrong results for large values.
**Cause:** Dis has only signed comparisons (BLTW = signed less-than).
**Fix:** XOR both operands with sign bit (0x8000000000000000) before
comparison, flipping the sign so unsigned order maps to signed order.

### B17: *ssa.Field Not Handled

**Symptom:** "unhandled SSA instruction: *ssa.Field" panic.
**Cause:** `*ssa.Field` (direct struct field extraction) was not implemented.
Only `*ssa.FieldAddr` (field address) was handled.
**Fix:** Implement `lowerField`: copy from struct base + field offset to
destination slot.

### B18: fmt.Printf Missing

**Symptom:** "unsupported function: fmt.Printf" error.
**Cause:** Only fmt.Sprintf and fmt.Println were intercepted.
**Fix:** Implement as Sprintf + sys.print.

### B19: panic(non-string) Crash

**Symptom:** VM crash on `panic(42)` (integer argument).
**Cause:** RAISE requires a string operand. Non-string panic values weren't
converted.
**Fix:** Emit CVTWC (int→string) before RAISE for non-string panic arguments.

### B20: Nil Error in Tuples Uses Wrong Representation

**Symptom:** `strconv.Atoi` returned non-nil error on success.
**Cause:** Nil error was materialized as `MOVW $(-1)` (H) for both words.
But nil error is a nil interface = 2 zero words, not H.
**Fix:** Nil error = `MOVW $0, tag; MOVW $0, value`.

### B21: println(bool) Prints "1" Instead of "true"

**Symptom:** `println(true)` outputs "1".
**Cause:** Bool was printed as integer.
**Fix:** Emit conditional branch to select "true"/"false" string before print.

### B22: constOperand Nil for Slice/Map/Chan/Func

**Symptom:** Nil comparisons for non-pointer-looking types failed.
**Cause:** `constOperand` only checked `*types.Pointer` for nil→H mapping.
Slices, maps, channels, and functions are also pointers in Dis.
**Fix:** Check all reference types: Pointer, Slice, Map, Chan, Signature.

### B23: for-range Loop Index Off-by-One

**Symptom:** `for i, v := range slice` skipped last element.
**Cause:** Loop exit condition used `BGTW` (>) instead of `BGEW` (>=) for
the length comparison.
**Fix:** Use `BGEW FP(i), FP(len), done`.

### B24: String-to-Rune-Slice Wrong Instruction

**Symptom:** Converting string to []rune crashed.
**Cause:** Used `INDW` (array addressing) to read string characters instead
of `INDC` (string character extraction).
**Fix:** Use INDC with correct operand order: `INDC str, idx, dst`.

### B25: Branch Operand Swap in Loop Exit

**Symptom:** Infinite loop in for-range.
**Cause:** `BGEW FP(len), FP(i), done` means "if len >= i goto done" — this
is almost always true (exits immediately or never).
**Fix:** `BGEW FP(i), FP(len), done` — "if i >= len goto done".

### B26: Empty Struct Slot Allocated at Offset 0 (REGLINK)

**Symptom:** Nil dereference after type asserting empty struct in CommaOk form.
Programs with `d, ok := iface.(EmptyStruct)` crash when the else branch runs.
**Cause:** `allocStructFields()` returns `baseSlot` which defaults to 0 when the
struct has no fields. Offset 0 in the frame is REGLINK (return address). Writing
the extracted value to 0(fp) corrupts the return address, causing a nil
dereference on function return.
**Fix:** Allocate a dummy word slot for empty structs in `allocStructFields()`
so the returned offset is always >= MaxTemp (64), never in the register area.

### B27: Type Assertion CommaOk Returns 0 Instead of H for Pointer Types

**Symptom:** `v, ok := x.(string)` segfaults when the assertion fails. The
non-match path returned `v = 0`, but pointer-typed zero values in Dis must be
H (-1). Setting a string slot to 0 causes a GC fault when accessed.
**Cause:** `lowerTypeAssert` emitted `MOVW $0, FP(dst)` for all types on the
non-match path. For pointer types (string, slice, etc.), the Dis zero value is
H = -1, not 0.
**Fix:** Check `dt.IsPtr` and emit `Imm(-1)` for pointer types.

### B28: Channel CommaOk Receive Returns ok=true After Close (Phantom Zero)

**Symptom:** `v, ok := <-ch` returns `ok=true` after `close(ch)` when the buffer
is empty. Expected `ok=false`.
**Cause:** `close()` injects a phantom zero value into the buffer via NBALT to
wake blocked receivers. A subsequent commaOk receive on the closed path picks up
this phantom value and reports `ok=true` because it can't distinguish phantom
zeros from real buffered values.
**Fix:** Added a buffered value count field at offset 24 in the channel wrapper
(expanded from 24 to 32 bytes). `lowerSend` increments the count; `close()` does
not. In `emitCloseAwareRecv` and `lowerChanNext`, the closed path checks the count
after NBALT succeeds: count > 0 means a real value (ok=true, decrement count);
count == 0 means a phantom zero (ok=false).

---

## Test Suite

### E2E Test Framework

`TestE2EPrograms` in `compiler_test.go` compiles each `.go` file in `testdata/`,
runs it on the Inferno emulator, and compares stdout to expected output.

```go
type testCase struct {
    file     string
    expected string
}

tests := []testCase{
    {"hello.go", "hello, infernode\n"},
    {"loop.go", "10\n45\n"},
    // ... 170+ more
}
```

The test harness uses `context.WithTimeout` to kill the emulator after 10
seconds (Inferno's emu doesn't always exit cleanly).

### Test Categories

| Category | Count | Description |
|---|---|---|
| Core language | ~40 | Variables, loops, conditionals, functions, methods |
| Data structures | ~20 | Arrays, slices, maps, structs, strings |
| Concurrency | ~15 | Goroutines, channels, select, buffered channels |
| Closures/HOF | ~10 | Closures, higher-order functions, method values |
| Error handling | ~10 | Panic, recover, defer, error interface |
| Type system | ~15 | Interfaces, type assert, type switch, embedding |
| Stdlib | ~15 | fmt, strings, strconv, math, sort, time |
| Real programs | ~22 | Quicksort, sieve, BST, pipeline, calculator, etc. |
| Tier 6 | 18 | Named types, closures, bit ops, nested structs |
| Lang completeness | 8 | &^, goto, labeled break, fallthrough, type aliases, struct embed, chan commaOk, 3-index slice |
| Multi-package | 4 | Multi-file, multi-pkg, chain imports, shared types |
| Benchmarks | 16 | Go vs Limbo performance comparison |

### Skipped Tests

- `selectrecv.go`, `map_range.go` — non-deterministic output (goroutine ordering)
- `sys*.go` — require Inferno-specific file system

### Running Tests

```sh
cd tools/godis
go test ./compiler/ -count=1 -timeout 120s       # all E2E tests
go test ./compiler/ -run TestE2EPrograms -count=1  # single-file tests only
go test ./compiler/ -run TestE2EMultiPackage       # multi-package tests
go test ./dis/ -count=1                            # bytecode round-trip tests
```

---

## Project Statistics

| Metric | Value |
|---|---|
| Total lines of code | ~14,200 |
| Compiler core (excl. tests) | ~9,200 |
| Largest file (lower.go) | 7,019 lines |
| Test code | ~3,500 |
| Dis bytecode library | ~2,000 |
| CLI tools | ~250 |
| E2E test programs | 172+ |
| Multi-package test scenarios | 4 |
| Benchmark programs | 16 |
| Supported Go features | Tiers 1-7 (see [Status](#status-and-limitations)) |
| Supported Sys functions | 15 |
| Intercepted stdlib packages | 14 (incl. embed, unsafe, math/cmplx) |
| Bugs found and fixed | 28 |
| VM opcodes used | 62+ |
| External dependencies | 1 (golang.org/x/tools) |

---

## Status and Limitations

### Supported Go Features (Tiers 1-6)

**Tier 1 — Core Language:**
Variables, constants (`const`/`iota`), arithmetic, comparisons, loops (`for`,
`for range`), conditionals (`if`/`else`, `switch`), functions, multiple return
values, methods (value and pointer receivers), recursive functions.

**Tier 2 — Data Structures:**
Arrays, slices (`make`, `append`, `copy`, `cap`, sub-slicing), strings (indexing,
slicing, concatenation, `[]byte` conversion, `[]rune` conversion), structs
(nested, embedded), maps (string and int keys), pointers and heap allocation.

**Tier 3 — Concurrency:**
Goroutines (`go`), channels (unbuffered, buffered, directional), `select`
(blocking, non-blocking with default), channel close, `for range` over channels,
`cap(ch)`.

**Tier 4 — Advanced Features:**
Closures (with captured variables), higher-order functions, method values,
`defer` (including defer with closures), `panic`/`recover`, interfaces (single
and multiple dispatch, type assertion, type switch, comma-ok, empty interface),
error interface, `init()` functions.

**Tier 5 — Standard Library:**
`fmt` (Sprintf, Printf, Println, Errorf with 10+ format verbs), `strings`
(11 functions), `strconv` (Itoa, Atoi, FormatInt), `math` (Abs, Sqrt, Min, Max),
`errors` (New), `os` (Exit), `sort` (Ints, Strings), `sync` (Mutex, WaitGroup,
Once), `time` (After, Duration), `log` (Println, Fatal), `io` (Reader, Writer).

**Tier 6 — Additional Coverage:**
Named type methods, struct embedding, composite interfaces, type assertion with
comma-ok, slices/maps of structs, recursive tree structures, named returns,
range with index, bit operations, defer with closure captures, directional
channels.

**Tier 7 — Language Completeness:**
Generics (monomorphization via `ssa.InstantiateGenerics`), complex numbers
(complex64/complex128 with full arithmetic), `go:embed` (compile-time file
embedding), `&^` bit-clear operator, `goto`, labeled `break`/`continue`,
`fallthrough`, 3-index slicing (`a[lo:hi:max]`), named return values, type
aliases (`type X = Y`), string ↔ `[]rune` conversions, method values
(`x.Method` as closure), struct embedding with promoted methods, multi-value
channel receive (`v, ok := <-ch`), `unsafe.Sizeof`.

### Go Language Spec Coverage

Systematic probing confirmed that the following features work through SSA
desugaring (no compiler changes needed): `goto`, labeled `break`/`continue`,
`fallthrough`, 3-index slicing, named return values, type aliases, method
values, struct embedding with promoted methods. The following required explicit
compiler implementation: `&^` operator, complex numbers, generics, `go:embed`,
`v, ok := <-ch` close detection, type assertion comma-ok pointer zero values.

### Known Limitations

1. **No goroutine unblock on close.** Goroutines blocked on RECV are not woken
   when the channel is closed from another goroutine. Close injects a phantom
   zero to wake one blocked receiver, but this is best-effort.
2. **No native maps.** Maps use sorted-array wrappers, not hash tables.
3. **Limited float formatting.** `%f`/`%g` use Dis CVTFC without precision
   control.
4. **No reflection.** `reflect` package is not supported.
5. **No cgo.** Cannot call C functions.
6. **Single-binary output.** All packages are inlined into one `.dis` file;
   no incremental/separate compilation.
7. **No garbage on stack.** Relies on VM's frame initialization for pointer
   slots; non-pointer slots may contain garbage from previous calls.
8. **Standard library is stub-only.** The 12+ intercepted stdlib packages
   provide type signatures for compilation but implementations are inlined
   as Dis instruction sequences, not full Go stdlib implementations.
