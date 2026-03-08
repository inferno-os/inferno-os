# Differences Between infernode and Standard Inferno®

**Purpose:** Document how infernode (derived from InferNode) differs from canonical Inferno® OS

**Reference:** https://github.com/inferno-os/inferno-os (standard Inferno®)

## High-Level Differences

### Philosophy

**Standard Inferno®:**
- Complete operating system with full GUI (tk/wm)
- Multiple applications (acme, charon browser, demos, etc.)
- Designed as standalone OS or hosted environment
- Full window manager and graphics stack

**infernode (InferNode derived):**
- "Chopped-top" minimal version
- Originally focused on Acme as primary interface
- Now: Headless-capable with console focus
- Stripped down for embedded/server use

## Directory Structure Differences

### Present in Standard Inferno®, MISSING from infernode

**Application Categories:**
- `appl/alphabet/` - Character/font applications
- `appl/collab/` - Collaboration tools
- `appl/demo/` - Demonstration programs
- `appl/ebook/` - E-book applications
- `appl/examples/` - Example programs
- `appl/spree/` - Spreadsheet/data tools
- `appl/tiny/` - Minimal applications

**System Components:**
- `libtk/` - Tk widget library (GUI)
- `libprefab/` - Prefab UI widgets
- `libfreetype/` - TrueType font rendering
- `liblogfs/` - Log filesystem
- `libnandfs/` - NAND flash filesystem
- `libdynld/` - Dynamic loading

**Resources:**
- More extensive `fonts/` directory
- `icons/` directory
- `locale/` for internationalization
- `services/` directory

**Native Kernels:**
- `os/` directory - Native (non-hosted) Inferno® kernels
- Boot code for standalone operation
- Hardware-specific ports

### Present in infernode, NOT in Standard Inferno®

**Custom Additions:**
- `appl/veltro/` - Veltro AI agent system
- `appl/xenith/` - Xenith text environment
- `docs/` - ARM64 porting documentation (our addition)
- Various test programs (test-*.b)

### Present in BOTH (Core Components)

- `appl/cmd/` - Command utilities ✓
- `appl/lib/` - Limbo libraries ✓
- `appl/acme/` - Acme editor ✓
- `appl/wm/` - Window manager ✓
- `appl/charon/` - Web browser (present but may not work)
- `emu/` - Emulator ✓
- `lib9/`, `libbio/`, etc. - Core C libraries ✓
- `libinterp/` - Dis VM interpreter ✓
- `limbo/` - Limbo compiler ✓
- `module/` - Limbo module interfaces ✓

## Startup and Initialization Differences

### emuinit.b

**Standard Inferno®:**
- Very similar to our version
- Loads Arg module and parses arguments
- Defaults to `sh -l` if no command specified

**infernode:**
- Nearly identical (we use standard emuinit)
- No significant differences

### lib/sh/profile

**Standard Inferno®:**
- **1 line:** Just a comment `# emu sh initialisation here`
- Minimal - expects users to customize
- No automatic host filesystem mounting

**infernode (InferNode):**
- **25 lines:** Full setup script
- Automatically mounts host filesystem with `trfs`
- Creates `/n/local` → Mac filesystem
- Sets up `acme-home` directory
- Binds tmp, creates directories
- **Much more opinionated/automated**

This is a MAJOR difference - InferNode assumes Acme workflow.

## Utilities Comparison

### Summary

**Standard Inferno®:** ~180 utilities in appl/cmd/
**infernode:** 157 utilities

### Missing from infernode (Notable)

From initial comparison:
- Some demo/example utilities
- Some specialized tools
- Window manager variants (wm/*)
- Graphics-specific tools

*Need detailed comparison to list all missing utilities*

### Utilities Present in Both

Core Unix-like commands present in both:
- ls, cat, cp, mv, rm, mkdir, cd
- grep, sed, tr, wc, sort
- ps, kill, date
- mount, bind, export, import
- telnet, ftp
- ed, diff
- tar, gzip, gunzip

## Library Differences

### Standard Inferno® Has

**GUI Libraries:**
- libtk - Tk widget library
- libprefab - Prefab UI components
- libfreetype - Font rendering

**Specialized:**
- liblogfs - Logging filesystem
- libnandfs - NAND flash support
- libdynld - Dynamic linking

### infernode Has (Subset)

Core libraries only:
- lib9, libbio, libmath
- libdraw, libmemdraw, libmemlayer (basic graphics)
- libinterp (Dis VM)
- libkeyring, libsec, libmp (crypto)

**Missing:** tk, prefab, freetype, logfs, nandfs, dynld

## Shell Differences

### Standard Inferno®

- Uses standard sh.b from inferno-os
- Basic exception handling

### infernode (InferNode)

**Originally:** Had broken exception handling (BADOP errors)
**Now:** Uses inferno64's sh.b (fixed exception handling)
**Better than:** Original InferNode version

## Graphics and Window Manager

### Standard Inferno®

- Full Tk widget library
- Complete window manager (wm/)
- Multiple WM applications
- Native graphics on various platforms

### infernode

- Acme editor (requires graphics)
- wm/ directory present but may not work
- **Headless mode:** No graphics, console only
- X11 backend available (not tested)
- Carbon backend obsolete (macOS)

## Namespace/Profile Differences

### Standard Inferno®

**Minimal profile:**
- User customizes everything
- No automatic mounts
- Clean slate approach

### infernode (InferNode)

**Opinionated profile:**
- Auto-mounts host filesystem
- Creates acme-home directory
- Sets up /n/local automatically
- Assumes Acme-centric workflow

**This is philosophical:**
- Standard Inferno®: Flexible, user-driven
- InferNode: Automated, Acme-focused

## Build System Differences

### Both Use

- `mk` build tool
- Similar mkfile structure
- limbo compiler

### Differences

**Standard Inferno®:**
- More platform targets
- Native OS builds (os/ directory)
- More configuration options

**infernode:**
- Focused on hosted (emu) only
- ARM64 macOS specific
- Simplified build

## For Developers and AI Assistants

### Key Differences to Remember

1. **Profile Automation:**
   - Standard: Empty, user-driven
   - infernode: Auto-mounts host fs, creates directories

2. **Utilities:**
   - infernode has ~157 of ~180 standard utilities
   - Missing: Some specialized/demo tools
   - Core utilities all present

3. **Libraries:**
   - infernode: Core only (no tk, prefab, freetype)
   - Standard: Full graphics stack

4. **Graphics:**
   - infernode: Headless-capable, X11 optional
   - Standard: Full GUI with tk/wm

5. **Purpose:**
   - infernode: Server/embedded, Acme development
   - Standard: Complete workstation OS

### What This Means

**infernode is NOT a full Inferno® replacement.**

It's a specialized distribution for:
- Console/headless operation
- Development work (with Acme if graphics available)
- Embedded systems
- Server applications
- 9P filesystem services

**Missing features vs standard Inferno®:**
- Full Tk GUI
- Many demo applications
- Some specialized libraries
- Native (non-hosted) operation

**Advantages of infernode:**
- Smaller, focused
- Headless-capable
- Automated host filesystem mounting
- Modern (ARM64 64-bit)

## Commands Known to Differ

### Startup

**Standard Inferno®:**
```
./emu
; (minimal prompt, empty namespace)
```

**infernode:**
```
./emu/MacOSX/o.emu -r.
; (prompt with /n/local auto-mounted)
```

### Accessing Host Files

**Standard Inferno®:**
```
; # Manual setup required
; mount -ac {mntgen} /n
; trfs '#U*' /n/local
; ls /n/local
```

**infernode:**
```
; # Already mounted by profile!
; ls /n/local/Users/pdfinn
```

## Compatibility Notes

### Scripts and Automation

**infernode is mostly compatible** with standard Inferno® scripts, but:

⚠️ **Assumptions may differ:**
- infernode assumes /n/local exists
- infernode has acme-home setup
- Some utilities missing may cause script failures

✅ **Core functionality identical:**
- Shell syntax same
- 9P protocol same
- Namespace operations same
- Most utilities same

### For AI Assistants

When working with infernode:
1. Assume headless mode (no tk/wm)
2. /n/local likely available (auto-mounted)
3. Core utilities present (ls, cat, grep, etc.)
4. Specialized tools may be missing
5. Shell works like standard Inferno® shell

## Detailed Utility Comparison

*To be completed: Full list of present/missing utilities*

### Definitely Present

- File: ls, cat, cp, mv, rm, mkdir, cd, pwd
- Text: grep, sed, tr, wc, sort, uniq
- Network: mount, bind, export, import, listen
- System: ps, kill, date
- Dev: ed, diff, limbo

### Likely Missing

- Some wm/* applications (window manager apps)
- Demo applications
- Specialized tools

## Recommendation for Users

**Use infernode if you need:**
- Headless Inferno®
- Console-based development
- 9P filesystem services
- Embedded/server applications
- Modern ARM64 support

**Use standard Inferno® if you need:**
- Full GUI environment
- Tk applications
- Complete application suite
- Native (non-hosted) operation
- Maximum compatibility

---

**This document helps developers and AI understand infernode's scope and limitations compared to full Inferno®.**
