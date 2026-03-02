# Inferno Development Guide for Agents

This document explains how to build, run, debug, and test software in Inferno OS.
Inferno is Plan 9-derived - it is NOT Unix, Linux, or macOS.

## Key Differences from Unix

| Unix/Linux | Inferno |
|------------|---------|
| bash | sh (Inferno shell) |
| Makefile | mkfile |
| GNU make | mk (Plan 9 make) |
| .c, .go files | .b files (Limbo) |
| ELF binaries | .dis files (Dis bytecode) |
| /bin | /dis |
| gcc/clang | limbo |

## Building Software

### Single File
```
limbo -I /module myfile.b
```
Produces `myfile.dis` in the current directory.

### Project with mkfile
```
cd /appl/myproject
mk
```

### mkfile Structure
```
<$ROOT/mkconfig

TARG=\
    myapp.dis\

SYSMODULES=\
    sys.m\
    draw.m\

DISBIN=$ROOT/dis/myapp

<$ROOT/mkfiles/mkdis
```

## Running Programs

```
/dis/path/to/program.dis [args]
```

Or from current directory:
```
./program.dis [args]
```

## Debugging

### Print Statements
```limbo
sys->print("debug: value is %d\n", value);
sys->fprint(sys->fildes(2), "error: %s\n", msg);  # stderr
```

### Error Messages
The `%r` format specifier shows the last system error:
```limbo
if(fd == nil)
    sys->print("open failed: %r\n");
```

### Exception Handling
```limbo
{
    # risky code
} exception e {
"fail:*" =>
    sys->print("caught failure: %s\n", e);
"*" =>
    sys->print("unexpected: %s\n", e);
}
```

### Common Errors
- `cannot load module` - path wrong or .dis doesn't exist
- `nil dereference` - variable not initialized or load failed
- `%r` messages - file not found, permission denied, etc.

## Testing Framework

Inferno has a Go-style testing framework. The API is similar to Go's `testing` package.

### Running Tests

All tests:
```
/dis/tests/runner.dis [-v]
```

Single test:
```
/dis/tests/example_test.dis [-v]
```

The `-v` flag enables verbose output.

### Test File Structure

Test files must end in `_test.b`. Example:

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

SRCFILE: con "/tests/my_test.b";  # for clickable errors

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
    t := testing->newTsrc(name, SRCFILE);
    {
        testfn(t);
    } exception {
    "fail:fatal" => ;
    "fail:skip" => ;
    "*" => t.failed = 1;
    }

    if(testing->done(t))
        passed++;
    else if(t.skipped)
        skipped++;
    else
        failed++;
}

testExample(t: ref T)
{
    t.asserteq(1 + 1, 2, "basic math");
    t.assertseq("hello", "hello", "string equality");
}

init(nil: ref Draw->Context, args: list of string)
{
    sys = load Sys Sys->PATH;
    testing = load Testing Testing->PATH;
    testing->init();

    # Check for -v flag
    for(a := args; a != nil; a = tl a)
        if(hd a == "-v")
            testing->verbose(1);

    run("Example", testExample);

    if(testing->summary(passed, failed, skipped) > 0)
        raise "fail:tests failed";
}
```

### Assertions

All assertions return 1 on success, 0 on failure:

| Function | Purpose |
|----------|---------|
| `t.assert(cond, msg)` | Boolean condition |
| `t.asserteq(got, want, msg)` | Integer equality |
| `t.assertne(got, notexpect, msg)` | Integer inequality |
| `t.assertseq(got, want, msg)` | String equality |
| `t.assertsne(got, notexpect, msg)` | String inequality |
| `t.assertnil(got, msg)` | String is empty |
| `t.assertnotnil(got, msg)` | String is not empty |

### Test Control

| Function | Purpose |
|----------|---------|
| `t.log(msg)` | Log message (shown with -v) |
| `t.error(msg)` | Mark failure, continue test |
| `t.fatal(msg)` | Mark failure, stop test |
| `t.skip(msg)` | Skip test with reason |

### Table-Driven Tests

```limbo
testAddTable(t: ref T)
{
    cases := array[] of {
        (1, 2, 3),
        (0, 0, 0),
        (-1, 1, 0),
    };

    for(i := 0; i < len cases; i++) {
        (a, b, want) := cases[i];
        got := add(a, b);
        t.asserteq(got, want, sys->sprint("add(%d, %d)", a, b));
    }
}
```

## Example Files

Study these for patterns:
- `/tests/example_test.b` - basic test structure
- `/tests/edit_test.b` - testing file operations
- `/tests/spawn_test.b` - testing concurrent code
- `/tests/veltro_security_test.b` - namespace security tests
- `/module/testing.m` - full API reference

## Veltro Namespace Security

Veltro agents run in restricted namespaces. When writing code that interacts with Veltro or its tools, be aware:

- **Agents cannot see**: project files (`.env`, `.git`, `CLAUDE.md`), host filesystem (`/n/local`), top-level commands in `/dis`, most of `/dev` and `/lib`
- **Agents can see**: `/dis/lib`, `/dis/veltro`, `/lib/veltro`, `/tool`, `/n/llm`, `/n/speech`, `/tmp/veltro/scratch`
- **Subagents** fork the parent's already-restricted namespace and can only narrow further
- **Security model**: FORKNS + bind-replace (see `appl/veltro/SECURITY.md`)

Security tests to run:
```
/dis/tests/veltro_security_test.dis -v
/dis/tests/veltro_concurrent_test.dis -v
```

## Building Tests

Tests are built like any other Limbo code:
```
cd /tests
mk
```

Or single file:
```
limbo -I /module mytest_test.b
```
