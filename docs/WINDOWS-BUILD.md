# Building InferNode on Windows

## Prerequisites

### Visual Studio 2022 Build Tools (required)

Download the free **Build Tools for Visual Studio 2022** from:
https://visualstudio.microsoft.com/downloads/ (scroll to "Tools for Visual Studio")

During installation, select the **"Desktop development with C++"** workload. This provides `cl.exe`, `ml64.exe`, `link.exe`, and `lib.exe`.

After installation, all build commands must be run from the **x64 Native Tools Command Prompt for VS 2022** (find it in the Start menu under "Visual Studio 2022"). This sets up the correct compiler paths. A regular PowerShell or CMD window will not work.

### SDL3 Development Package (optional, for GUI)

Only needed if you want the graphical interface (Xenith, wm/wm). The headless build has no SDL3 dependency.

1. Go to https://github.com/libsdl-org/SDL/releases
2. Download `SDL3-devel-<version>-VC.zip`
3. Extract so the structure is: `SDL3-dev/SDL3-<version>/include/SDL3/SDL.h`

The build script searches for SDL3 in this order:
- `-SDL3Dir` parameter
- `SDL3DIR` environment variable
- `SDL3-dev/SDL3-*/` in the project root
- vcpkg (`C:\vcpkg\installed\x64-windows`)

## Building — Headless

Open **x64 Native Tools Command Prompt for VS 2022**, `cd` to the project root, then:

```powershell
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1
```

This builds:
- `Nt\amd64\bin\mk.exe` — Plan 9 build tool
- `Nt\amd64\bin\limbo.exe` — Limbo compiler
- `Nt\amd64\lib\*.lib` — All static libraries
- `emu\Nt\o.emu.exe` — Headless emulator
- `dis\**\*.dis` — Compiled Dis bytecode (630+ files)

Build time is typically 1-2 minutes.

## Building — SDL3 GUI

The GUI build requires the headless build to be done first (it reuses the libraries).

```powershell
powershell -ExecutionPolicy Bypass -File build-windows-amd64.ps1    # libraries + limbo + bytecode
powershell -ExecutionPolicy Bypass -File build-windows-sdl3.ps1     # GUI emulator
```

After a successful GUI build, `emu\Nt\` will contain both `o.emu.exe` (rebuilt with GUI support) and `SDL3.dll`.

You can also point to a custom SDL3 location:

```powershell
powershell -ExecutionPolicy Bypass -File build-windows-sdl3.ps1 -SDL3Dir "C:\path\to\SDL3"
```

## Running

All commands are run from the project root directory.

### Headless Shell

```powershell
.\emu\Nt\o.emu.exe -r .
```

Or with the shell profile loaded (sets up PATH, creates `/tmp`, etc.):

```powershell
.\emu\Nt\o.emu.exe -r . sh -l
```

### Window Manager (GUI build)

```powershell
.\emu\Nt\o.emu.exe -g 1024x768 -r . wm/wm
```

### Xenith (GUI build)

```powershell
.\emu\Nt\o.emu.exe -g 1024x768 -r . sh -l -c xenith
```

### Lucifer (GUI build)

Lucifer is a three-zone AI interface (conversation, presentation, context) designed for human-AI collaboration. Launch it with:

```powershell
.\run-lucifer.ps1
.\run-lucifer.ps1 -Width 1920 -Height 1080    # custom resolution
```

Or manually:

```powershell
.\emu\Nt\o.emu.exe -g 1280x800 -pheap=512m -pmain=512m -pimage=512m -r . sh -l -c 'luciuisrv; echo activity create Main > /n/ui/ctl; lucifer'
```

### Common Flags

| Flag | Description |
|------|-------------|
| `-r .` | Use current directory as Inferno root filesystem |
| `-g WxH` | Set window size (e.g., `-g 1024x768`, `-g 1920x1080`) |
| `-c0` | Interpreter only (default on Windows) |
| `-c1` | Enable JIT compiler (not yet available on Windows) |

## Troubleshooting

### "cl.exe is not recognized"

You're not in the Visual Studio Developer Command Prompt. Open **x64 Native Tools Command Prompt for VS 2022** from the Start menu, or run:

```cmd
"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
```

### "Running scripts is disabled on this system"

PowerShell execution policy is blocking the build script. Use the `-ExecutionPolicy Bypass` flag as shown in the build commands above, or set the policy for your user:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Can't open font file" or garbled text

Font files have Windows-style line endings (CRLF). Inferno's font parser requires Unix line endings (LF).

Fix: ensure `.gitattributes` is present at the project root (it should be — it's tracked in git). Then re-checkout the font files:

```powershell
git checkout -- fonts/
```

If you cloned before `.gitattributes` existed, you may need to normalize the whole repo:

```bash
git rm --cached -r .
git reset --hard
```

### Window appears but shows white screen

This is usually the font issue described above. After fixing line endings, rebuild:

```powershell
git checkout -- fonts/
powershell -ExecutionPolicy Bypass -File build-windows-sdl3.ps1
```

### "SDL3 not found"

The GUI build script can't locate SDL3. Make sure you either:
- Extracted the SDL3 development package to `SDL3-dev/` in the project root
- Set the `SDL3DIR` environment variable
- Installed via vcpkg (`vcpkg install sdl3:x64-windows`)

### "Libraries not found. Run build-windows-amd64.ps1 first."

The SDL3 GUI build depends on libraries built by the headless build script. Run `build-windows-amd64.ps1` before `build-windows-sdl3.ps1`.

## Technical Notes

- Windows uses the Dis **interpreter only** (no JIT compiler yet). Performance is adequate for interactive use.
- The build uses `/MT` (static CRT) to allow Inferno's pool allocator to override `malloc`/`free`.
- MSVC does not support `__int128` — the build uses a shim (`uint128.h`) with `_umul128()` intrinsics for x25519 and ECC.
- All files are built with LF line endings (enforced by `.gitattributes`). This is critical — Inferno's font parser, shell profile, and other tools cannot handle CRLF.
