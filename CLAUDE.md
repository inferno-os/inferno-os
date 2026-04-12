# Infernode - Development Guide for Claude

This guide ensures Claude Code works correctly with the Infernode (Inferno® OS) codebase.

## JIT Compiler Availability

**AMD64 (x86-64) and ARM64 have JIT compilers.** The ARM64 JIT (`libinterp/comp-arm64.c`) supports both macOS (Apple Silicon) and Linux (e.g. NVIDIA Jetson). Run with `emu -c1` to enable JIT compilation, `emu -c0` for interpreter only.

When compiling Limbo code:
- **Use the native `limbo` compiler** (`MacOSX/arm64/bin/limbo`) - produces portable Dis bytecode
- **Do NOT use the hosted limbo** (`dis/limbo.dis` inside emu) - it sets `MUSTCOMPILE` flag requiring JIT

If you see "compiler required" errors when running `.dis` files, you compiled with the wrong limbo. Recompile using the native compiler.

## Building Limbo Code

**Always use Inferno®'s native build tools from macOS**, not Plan 9 Port or commands inside Inferno. This ensures the build environment is compatible with the target Inferno® system - the same compiler and mk that ship with Inferno® are used to build code that runs on Inferno®.

### Bootstrap (first time after clone)

The native build tools (`mk`, `limbo`) are not checked into git. Bootstrap them:
```sh
./makemk.sh            # builds mk from source using cc (~30s)
```
Then build the rest (libraries, limbo compiler, emulator) using the platform build script or `mk install`.

### Environment Setup

From the project root, set these environment variables:
```sh
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH
```

The native tools are built to:
- `MacOSX/arm64/bin/mk` - Plan 9 mk (Inferno's build tool)
- `MacOSX/arm64/bin/limbo` - Limbo compiler

### Dis Files: What's Tracked and What's Not

The `dis/` directory (the Inferno runtime tree) **is tracked in git**. This is intentional — Inferno is a self-hosting OS, and `dis/` is its `/usr/bin`. Without pre-built `.dis` files, a fresh clone can't boot: no shell, no `cat`, no `ls`. Upstream Inferno OS tracks them for the same reason.

However, **build artifacts in source directories are not tracked**:
- `appl/**/*.dis` — intermediate build outputs (`.gitignore`d)
- `tests/**/*.dis` — compiled tests (`.gitignore`d)
- `dis/tests/*.dis` — test bytecode in the runtime tree (`.gitignore`d)

This means: the runtime tree ships pre-built, but you never commit `.dis` files from `appl/` or `tests/`.

**The stale bytecode problem:** When a `.m` interface file changes (e.g. `module/widget.m`), every `.dis` compiled against the old interface becomes stale. The Dis VM rejects stale modules at load time with `link typecheck` errors — apps show blank tabs, commands fail to load, and everything looks broken even though the source is fine. This is the most common class of post-pull breakage.

**The solution:** A `post-merge` git hook automatically detects which `.m` and `.b` files changed after `git pull` and rebuilds the affected `.dis` directories. Install it once after cloning:

```sh
./hooks/install.sh
```

After that, every `git pull` triggers an automatic rebuild of stale bytecode. See `hooks/post-merge` for details.

### Build Commands

Build from macOS terminal (not inside Inferno):

```sh
# AFTER FRESH CLONE: Build all commands
cd appl/cmd
mk install

# Build tests
cd tests
mk install

# Clean and rebuild
mk nuke
mk install

# Build a specific directory
cd appl/lib
mk testing.dis
```

### Why Native Tools?

Using Inferno®'s native mk and limbo ensures:
1. **Compatibility** - Same toolchain that built Inferno® builds your code
2. **Correct SHELLTYPE** - mkconfig uses `SHELLTYPE=sh` for macOS /bin/sh
3. **No PATH conflicts** - Avoids mixing Plan 9 Port tools with Inferno® tools

Do NOT:
- Run `mk` inside Inferno (SHELLTYPE mismatch)
- Use Plan 9 Port's mk (may have subtle incompatibilities)
- Use bash-isms like `&&` to chain commands (use `;` or separate commands)

## Inferno® Shell Differences

The Inferno® shell is rc-style, not POSIX sh:
- No `&&` operator - use `;` or separate commands
- `for` loops: `for i in $list { commands }` not `for i in $list; do ... done`
- Different quoting rules

## Testing System

Infernode uses a custom testing framework (`module/testing.m`) for Limbo unit tests.

### Running Tests

Tests run inside the Inferno® emulator. From the project root:

```sh
# Set up environment first
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH

# Build all tests
cd tests
mk install

# Run all tests via the test runner (inside Inferno)
# The emu command launches Inferno and runs the test runner
./emu/MacOSX/o.emu -r. /tests/runner.dis

# Run a specific test file
./emu/MacOSX/o.emu -r. /tests/asyncio_test.dis

# Run with verbose output
./emu/MacOSX/o.emu -r. /tests/runner.dis -v
```

### Writing Tests

Test files follow this structure:

```limbo
implement MyTest;

include "sys.m";
    sys: Sys;

include "draw.m";

include "testing.m";
    testing: Testing;
    T: import testing;

MyTest: module
{
    init: fn(nil: ref Draw->Context, args: list of string);
};

# Source file path for clickable error addresses
SRCFILE: con "/tests/mytest.b";

# Global counters
passed := 0;
failed := 0;
skipped := 0;

# Test runner helper
run(name: string, testfn: ref fn(t: ref T))
{
    t := testing->newTsrc(name, SRCFILE);
    {
        testfn(t);
    } exception {
    "fail:fatal" =>
        ;
    "fail:skip" =>
        ;
    * =>
        t.failed = 1;
    }

    if(testing->done(t))
        passed++;
    else if(t.skipped)
        skipped++;
    else
        failed++;
}

# Example test function
testExample(t: ref T)
{
    t.assert(1 == 1, "basic math works");
    t.asserteq(2 + 2, 4, "addition");
    t.assertseq("hello", "hello", "string equality");

    # Log messages (shown in verbose mode)
    t.log("this is a log message");

    # Skip a test
    # t.skip("reason for skipping");

    # Fatal error (stops this test)
    # t.fatal("something went very wrong");
}

init(nil: ref Draw->Context, args: list of string)
{
    sys = load Sys Sys->PATH;
    testing = load Testing Testing->PATH;

    if(testing == nil) {
        sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
        raise "fail:cannot load testing";
    }

    testing->init();

    # Parse -v flag for verbose mode
    for(a := args; a != nil; a = tl a) {
        if(hd a == "-v")
            testing->verbose(1);
    }

    # Run tests
    run("Example", testExample);

    # Print summary and exit with failure if any tests failed
    if(testing->summary(passed, failed, skipped) > 0)
        raise "fail:tests failed";
}
```

### Testing API Reference

The `T` adt provides these methods:

| Method | Description |
|--------|-------------|
| `t.log(msg)` | Log a message (shown in verbose mode) |
| `t.error(msg)` | Report failure but continue test |
| `t.fatal(msg)` | Report failure and stop test |
| `t.skip(msg)` | Skip this test |
| `t.assert(cond, msg)` | Assert condition is true |
| `t.asserteq(got, want, msg)` | Assert integers are equal |
| `t.assertne(got, notexpect, msg)` | Assert integers are not equal |
| `t.assertseq(got, want, msg)` | Assert strings are equal |
| `t.assertsne(got, notexpect, msg)` | Assert strings are not equal |
| `t.assertnil(got, msg)` | Assert string is nil/empty |
| `t.assertnotnil(got, msg)` | Assert string is not nil/empty |

### Test File Naming

- Test files must end with `_test.b`
- Place tests in the `tests/` directory
- The test runner (`tests/runner.dis`) automatically discovers `*_test.dis` files

### Clickable Error Addresses

When a test fails, the output includes clickable addresses that work in Xenith:

```
FAIL: MyTest/Example
    /tests/mytest.b:/testExample/ assertion failed: something broke
```

To enable this, define `SRCFILE` and use `testing->newTsrc(name, SRCFILE)`.

### Testing Async/Concurrent Code

For testing spawned tasks and channels:

```limbo
testAsyncOperation(t: ref T)
{
    result := chan of string;

    # Spawn a task
    spawn worker(result);

    # Wait with timeout
    timeout := chan of int;
    spawn timeoutTask(timeout, 1000);  # 1 second

    alt {
        r := <-result =>
            t.assertseq(r, "expected", "worker result");
        <-timeout =>
            t.fatal("operation timed out");
    }
}

worker(result: chan of string)
{
    # Do work...
    result <-= "expected";
}

timeoutTask(ch: chan of int, ms: int)
{
    sys->sleep(ms);
    ch <-= 1;
}
```

### Test Categories

| Test File | Purpose |
|-----------|---------|
| `example_test.b` | Reference template for new tests |
| `asyncio_test.b` | Async I/O, channels, spawned tasks |
| `crypto_test.b` | Cryptographic operations |
| `spawn_test.b` | Process spawning |
| `spawn_exec_test.b` | Process exec after spawn |
| `tcp_test.b` | TCP networking |
| `9p_export_test.b` | 9P protocol export |
| `tempfile_test.b` | Temporary file operations |
| `stderr_test.b` | Standard error output |
| `hello_test.b` | Basic smoke test |
| `veltro_test.b` | Veltro agent system |
| `veltro_tools_test.b` | Veltro tool modules |
| `veltro_security_test.b` | Veltro namespace security |
| `veltro_concurrent_test.b` | Veltro concurrency |
| `agent_test.b` | Agent operations |
| `edit_test.b` | Edit operations |
| `xenith_concurrency_test.b` | Xenith concurrent operations |
| `xenith_exit_test.b` | Xenith exit handling |
| `sdl3_test.b` | SDL3 GUI backend |

Shell tests also exist in `tests/inferno/` (run inside Inferno) and `tests/host/` (run on the host OS).

## Project Structure

```
infernode/
├── MacOSX/arm64/bin/    # Native macOS build tools (built by makemk.sh + mk)
├── emu/                 # Emulator source and binaries
│   ├── MacOSX/          #   macOS emulator (o.emu binary)
│   ├── Linux/           #   Linux emulator (build with build-linux-*.sh)
│   └── port/            #   Platform-independent emulator source
├── appl/                # Limbo application source (~700 .b files)
│   ├── cmd/             #   Command-line utilities
│   ├── lib/             #   Library modules
│   ├── veltro/          #   Veltro AI agent system
│   ├── xenith/          #   Xenith text environment (Acme fork)
│   ├── acme/            #   Acme text editor
│   ├── wm/              #   Window manager
│   └── svc/             #   Services (httpd, etc.)
├── module/              # Limbo module interfaces (.m files)
├── tests/               # Unit tests (Limbo + shell)
│   ├── host/            #   Host-side shell tests
│   ├── inferno/         #   Inferno-side shell tests
│   └── testing/         #   Testing framework self-tests
├── dis/                 # Compiled Dis bytecode (~630 .dis files)
├── lib/                 # Runtime data (fonts, shell profile, etc.)
│   └── veltro/          #   Veltro tools, agents, reminders
├── libinterp/           # Dis VM interpreter and JIT compilers
├── docs/                # Technical documentation (100+ files)
├── formal-verification/ # CBMC, TLA+, SPIN verification
├── hooks/               # Git hooks (run ./hooks/install.sh after clone)
├── mkfiles/             # Shared mk build rules
├── mkconfig             # Build configuration (auto-detects platform)
├── .github/workflows/   # CI/CD (ci, security, scorecard)
└── build-*.sh           # Platform build scripts
```
