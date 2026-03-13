# InferNode - Quick Start Guide

## Running Inferno®

```bash
# Linux x86_64 (Intel/AMD) - build first, then run
./build-linux-amd64.sh
./emu/Linux/o.emu -r.

# Linux ARM64 (Jetson, Raspberry Pi, etc.) - build first, then run
./build-linux-arm64.sh
./emu/Linux/o.emu -r.

# macOS ARM64 (Apple Silicon)
./emu/MacOSX/o.emu -r.
```

```powershell
# Windows x86_64 (from x64 Native Tools Command Prompt)
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1
.\emu\Nt\o.emu.exe -r .
```

### What does `-r.` mean?

The `-r` option sets the **root directory** for the Inferno® filesystem - where the emulator looks for `/dis`, `/module`, `/fonts`, and other Inferno® files.

- `-r.` = use current directory (`.`) as root
- `-r/opt/inferno` = use `/opt/inferno` as root (path is host filesystem convention)
- No `-r` = use compiled-in default (`/usr/inferno`)

Using `-r.` lets you run directly from the source tree without installing anywhere.

## After Cloning

Install the post-merge git hook to prevent stale bytecode after pulls:

```bash
./hooks/install.sh
```

This hook runs automatically after every `git pull` or `git merge`. It detects which `.m` (interface) and `.b` (source) files changed and rebuilds the affected `.dis` files. Without it, pulling interface changes can leave you with stale `.dis` files that fail at load time with `link typecheck` errors.

### Why are `.dis` files in git?

Inferno is a self-hosting OS — the `dis/` directory is its runtime, like `/usr/bin` on Unix. Without pre-built `.dis` files, a fresh clone has no shell, no `cat`, no `ls`. The runtime tree (`dis/`) is tracked so the system boots immediately after clone.

Build artifacts in source directories (`appl/**/*.dis`, `tests/**/*.dis`) are **not** tracked — only the runtime tree.

The trade-off: tracked `.dis` files can go stale when `.m` interfaces change between commits. The post-merge hook closes that gap automatically.

## First Steps

You'll see the `;` prompt. Try these commands:

```
; pwd
/
; date
Sat Jan 10 07:46:10 EST 2026
; ls
[directory listing]
; cat /dev/sysctl
Fourth Edition (20120928)
; cat /dev/user
pdfinn
; echo hello world
hello world
```

## Available Commands

After building (see Building section below):
- **Filesystem**: ls, pwd, cat, rm, mv, cp, mkdir, cd
- **System**: ps, kill, date, mount, bind
- **Network**: mntgen, trfs, os
- **Utilities**: du, wc, grep, ftest, echo

**Note:** The runtime `.dis` files in `dis/` are tracked in git, so basic commands work after clone. If you see `link typecheck` errors, run `./hooks/install.sh` and pull again, or rebuild manually with `mk install` in the affected `appl/` subdirectory.

## Building

### Linux x86_64 (Intel/AMD)

```bash
./build-linux-amd64.sh
```

This bootstraps the `mk` build tool, compiles all libraries, builds the `limbo` compiler, creates the headless emulator, and compiles the Dis bytecode applications.

### Linux ARM64

```bash
./build-linux-arm64.sh
```

Same process as x86_64, but for ARM64 platforms like Jetson or Raspberry Pi.

### macOS ARM64

```bash
export PATH="$PWD/X/arm64/bin:$PATH"
mk install
```

### Windows x86_64

Requires Visual Studio 2022 Build Tools (free). Open **x64 Native Tools Command Prompt for VS 2022**, then:

```powershell
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1
```

This builds libraries, the `limbo` compiler, the headless emulator, and all Dis bytecode. For SDL3 GUI support, see [docs/WINDOWS-BUILD.md](docs/WINDOWS-BUILD.md).

## Architecture Notes

The emulator (`o.emu`) is a hosted Inferno® - it runs as a process on your host OS and provides:
- Dis virtual machine (executes `.dis` bytecode)
- Virtual filesystem namespace
- Host filesystem access via `/`
- Network stack

Inferno® programs are written in Limbo and compiled to Dis bytecode (`.dis` files in `/dis`).

## The 64-bit Fix

The critical fix for 64-bit platforms was changing pool quanta from 31 to 127 in `emu/port/alloc.c` to handle 64-bit pointer alignment.

---

**Status: 64-bit Inferno® is working on x86_64 Linux, ARM64 Linux, ARM64 macOS, and x86_64 Windows**
