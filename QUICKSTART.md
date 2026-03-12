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

**Note:** `.dis` files are not tracked in git. After a fresh clone, run `mk install` in `appl/cmd` to build these commands.

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
