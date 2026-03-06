#
# Build script for Windows x86-64 (amd64) - SDL3 GUI Emulator
# Run this from a Visual Studio Developer Command Prompt (x64).
#
# Prerequisites:
#   - MSVC (cl.exe, ml64.exe, link.exe) in PATH
#   - SDL3 installed (vcpkg, manual install, or set SDL3DIR)
#   - Run build-windows-amd64.ps1 first (builds libraries)
#
# Usage:
#   .\build-windows-sdl3.ps1
#   .\build-windows-sdl3.ps1 -SDL3Dir "C:\path\to\sdl3"
#

param(
    [string]$SDL3Dir = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== InferNode Windows x86-64 SDL3 GUI Build ===" -ForegroundColor Cyan
Write-Host ""

$ROOT = (Get-Location).Path
$BinDir = "$ROOT\Nt\amd64\bin"
$LibDir = "$ROOT\Nt\amd64\lib"

# Verify libraries were built first
if (-not (Test-Path "$LibDir\libinterp.lib")) {
    Write-Host "ERROR: Libraries not found. Run build-windows-amd64.ps1 first." -ForegroundColor Red
    exit 1
}

# =============================================
# Find SDL3
# =============================================
$sdl3Found = $false
$sdl3Include = ""
$sdl3Lib = ""
$sdl3DllDir = ""

# Helper: resolve lib/dll paths (official SDK has lib/x64/, vcpkg has lib/)
function Resolve-SDL3Paths {
    param([string]$Dir)
    $inc = "$Dir\include"
    $lib = ""; $dll = ""
    if (Test-Path "$Dir\lib\x64\SDL3.lib") {
        $lib = "$Dir\lib\x64\SDL3.lib"
        $dll = "$Dir\lib\x64"
    } elseif (Test-Path "$Dir\lib\SDL3.lib") {
        $lib = "$Dir\lib\SDL3.lib"
        $dll = "$Dir\bin"
    }
    return @{ Include=$inc; Lib=$lib; DllDir=$dll }
}

# Check explicit parameter
if ($SDL3Dir -ne "" -and (Test-Path "$SDL3Dir\include\SDL3\SDL.h")) {
    $paths = Resolve-SDL3Paths $SDL3Dir
    $sdl3Include = $paths.Include; $sdl3Lib = $paths.Lib; $sdl3DllDir = $paths.DllDir
    $sdl3Found = $true
    Write-Host "SDL3 found at: $SDL3Dir (parameter)" -ForegroundColor Green
}

# Check environment variable
if (-not $sdl3Found -and $env:SDL3DIR -and (Test-Path "$env:SDL3DIR\include\SDL3\SDL.h")) {
    $SDL3Dir = $env:SDL3DIR
    $paths = Resolve-SDL3Paths $SDL3Dir
    $sdl3Include = $paths.Include; $sdl3Lib = $paths.Lib; $sdl3DllDir = $paths.DllDir
    $sdl3Found = $true
    Write-Host "SDL3 found at: $SDL3Dir (environment)" -ForegroundColor Green
}

# Check local SDL3-dev directory (from official GitHub release)
if (-not $sdl3Found) {
    $localPaths = @(
        "$ROOT\SDL3-dev\SDL3-3.4.0",
        "$ROOT\SDL3-dev\SDL3-*"
    )
    foreach ($lp in $localPaths) {
        $resolved = Resolve-Path $lp -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved -and (Test-Path "$($resolved.Path)\include\SDL3\SDL.h")) {
            $SDL3Dir = $resolved.Path
            $paths = Resolve-SDL3Paths $SDL3Dir
            $sdl3Include = $paths.Include; $sdl3Lib = $paths.Lib; $sdl3DllDir = $paths.DllDir
            $sdl3Found = $true
            Write-Host "SDL3 found at: $SDL3Dir (local)" -ForegroundColor Green
            break
        }
    }
}

# Check vcpkg
if (-not $sdl3Found) {
    $vcpkgPaths = @(
        "C:\vcpkg\installed\x64-windows",
        "$env:VCPKG_ROOT\installed\x64-windows",
        "$env:USERPROFILE\vcpkg\installed\x64-windows"
    )
    foreach ($vp in $vcpkgPaths) {
        if (Test-Path "$vp\include\SDL3\SDL.h") {
            $SDL3Dir = $vp
            $paths = Resolve-SDL3Paths $SDL3Dir
            $sdl3Include = $paths.Include; $sdl3Lib = $paths.Lib; $sdl3DllDir = $paths.DllDir
            $sdl3Found = $true
            Write-Host "SDL3 found at: $vp (vcpkg)" -ForegroundColor Green
            break
        }
    }
}

if (-not $sdl3Found) {
    Write-Host "ERROR: SDL3 not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install SDL3 via one of:"
    Write-Host "  Download from https://github.com/libsdl-org/SDL/releases (SDL3-devel-*-VC.zip)"
    Write-Host "  Extract to $ROOT\SDL3-dev\"
    Write-Host "  Or: vcpkg install sdl3:x64-windows"
    Write-Host "  Or: set SDL3DIR environment variable"
    Write-Host "  Or: pass -SDL3Dir parameter"
    exit 1
}

# Check for MSVC tools
$tools = @("cl.exe", "ml64.exe", "link.exe")
foreach ($tool in $tools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: $tool not found. Run from a Visual Studio Developer Command Prompt (x64)." -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# =============================================
# Build SDL3 GUI Emulator
# =============================================
Write-Host "=== Building SDL3 GUI Emulator ===" -ForegroundColor Cyan
Push-Location "$ROOT\emu\Nt"

# Clean all .obj files for a fresh GUI build
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$emuCFlags = @(
    "/nologo", "/c", "/O2", "/Gy", "/GF", "/MT",
    "/W3", "/wd4018", "/wd4244", "/wd4245", "/wd4068",
    "/wd4090", "/wd4554", "/wd4146", "/wd4996", "/wd4305",
    "/wd4102", "/wd4761",
    "/DEMU", "/D_AMD64_", "/DWINDOWS_AMD64", "/DGUI_SDL3",
    "/I.", "/I..\port",
    "/I$ROOT\Nt\amd64\include",
    "/I$ROOT\include",
    "/I$ROOT\libinterp",
    "/I$sdl3Include"
)

# Platform-specific source files (from emu/Nt/)
Write-Host "  Compiling platform sources..."
$ntSources = @(
    "os.c", "cmd.c", "no_win.c", "fp.c",
    "nocomp.c",
    "devfs.c",
    "ipif6.c"
)
foreach ($src in $ntSources) {
    if (Test-Path $src) {
        Write-Host "    $src"
        & cl.exe @emuCFlags $src
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to compile $src" -ForegroundColor Red
            exit 1
        }
    }
}

# Assemble AMD64 assembly
Write-Host "  Assembling asm-amd64-win.asm..."
& ml64.exe /nologo /c asm-amd64-win.asm
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to assemble asm-amd64-win.asm" -ForegroundColor Red
    exit 1
}

# Compile SDL3 backend from port/
Write-Host "  Compiling draw-sdl3.c..."
& cl.exe @emuCFlags "..\port\draw-sdl3.c"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to compile draw-sdl3.c" -ForegroundColor Red
    exit 1
}

# Port source files (from emu/port/)
Write-Host "  Compiling port sources..."
$portSources = @(
    "alloc.c", "cache.c", "chan.c", "dev.c", "devtab.c", "dial.c",
    "dis.c", "discall.c", "env.c", "error.c", "errstr.c",
    "exception.c", "exportfs.c", "inferno.c", "latin1.c",
    "main.c", "parse.c", "pgrp.c", "print.c", "proc.c",
    "qio.c", "random.c", "sysfile.c", "uqid.c",
    "lock.c",
    "devcons.c", "devdraw.c", "devdup.c", "devenv.c", "devip.c",
    "devmnt.c", "devpipe.c", "devpointer.c", "devprog.c", "devroot.c",
    "devsnarf.c", "devsrv.c", "devssl.c", "devcmd.c", "devwmsz.c",
    "ipaux.c", "srv.c"
)
foreach ($src in $portSources) {
    $srcPath = "..\port\$src"
    if (Test-Path $srcPath) {
        Write-Host "    port/$src"
        & cl.exe @emuCFlags $srcPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to compile port/$src" -ForegroundColor Red
            exit 1
        }
    }
}

# Generate GUI config .c file
Write-Host "  Generating emu-gui-config.c..."
$guiConfigC = @"
#include "dat.h"
#include "fns.h"
#include "error.h"
#include "interp.h"

/*
 * Root filesystem tables.
 * qid 0: / (root)
 * qid 1: dev
 * qid 2: fd
 * qid 3: prog
 * qid 4: net
 * qid 5: chan
 * qid 6: env
 */
int rootmaxq = 7;

Dirtab roottab[7] = {
	"",	{0, 0, QTDIR},	0,	0555,
	"dev",	{1, 0, QTDIR},	0,	0555,
	"fd",	{2, 0, QTDIR},	0,	0555,
	"prog",	{3, 0, QTDIR},	0,	0555,
	"net",	{4, 0, QTDIR},	0,	0555,
	"chan",	{5, 0, QTDIR},	0,	0555,
	"env",	{6, 0, QTDIR},	0,	0555,
};

Rootdata rootdata[7] = {
	0,	&roottab[1],	6,	nil,
	0,	nil,	0,	nil,
	0,	nil,	0,	nil,
	0,	nil,	0,	nil,
	0,	nil,	0,	nil,
	0,	nil,	0,	nil,
	0,	nil,	0,	nil,
};

extern Dev rootdevtab;
extern Dev consdevtab;
extern Dev envdevtab;
extern Dev mntdevtab;
extern Dev pipedevtab;
extern Dev progdevtab;
extern Dev srvdevtab;
extern Dev dupdevtab;
extern Dev ssldevtab;
extern Dev fsdevtab;
extern Dev cmddevtab;
extern Dev drawdevtab;
extern Dev ipdevtab;
extern Dev pointerdevtab;
extern Dev snarfdevtab;
extern Dev wmszdevtab;

Dev* devtab[]={
	&rootdevtab,
	&consdevtab,
	&envdevtab,
	&mntdevtab,
	&pipedevtab,
	&progdevtab,
	&srvdevtab,
	&dupdevtab,
	&ssldevtab,
	&fsdevtab,
	&cmddevtab,
	&drawdevtab,
	&ipdevtab,
	&pointerdevtab,
	&snarfdevtab,
	&wmszdevtab,
	nil,
};

void links(void){
}

extern void sysmodinit(void);
extern void drawmodinit(void);
extern void mathmodinit(void);
extern void srvmodinit(void);
extern void keyringmodinit(void);
extern void cryptmodinit(void);
extern void ipintsmodinit(void);
void modinit(void){
	sysmodinit();
	drawmodinit();
	mathmodinit();
	srvmodinit();
	keyringmodinit();
	cryptmodinit();
	ipintsmodinit();
}

char* conffile = "emu-gui";
ulong kerndate = 0;
"@
$guiConfigC | Set-Content -Path "emu-gui-config.c" -Encoding ASCII
& cl.exe @emuCFlags "emu-gui-config.c"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to compile emu-gui-config.c" -ForegroundColor Red
    exit 1
}

# Link the GUI emulator
Write-Host "  Linking o.emu.exe (SDL3 GUI)..."
$allObjs = Get-ChildItem -Path "." -Filter "*.obj" | ForEach-Object { $_.Name }

& link.exe /nologo /subsystem:console `
    "/OUT:o.emu.exe" `
    @allObjs `
    "$LibDir\libinterp.lib" `
    "$LibDir\libkeyring.lib" `
    "$LibDir\libsec.lib" `
    "$LibDir\libmp.lib" `
    "$LibDir\libmath.lib" `
    "$LibDir\libdraw.lib" `
    "$LibDir\libmemlayer.lib" `
    "$LibDir\libmemdraw.lib" `
    "$LibDir\lib9.lib" `
    $sdl3Lib `
    ws2_32.lib user32.lib gdi32.lib advapi32.lib winmm.lib mpr.lib kernel32.lib shell32.lib
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to link o.emu.exe" -ForegroundColor Red
    exit 1
}
Write-Host "  o.emu.exe (SDL3 GUI) built" -ForegroundColor Green
Pop-Location

# Copy SDL3.dll next to the executable if available
if ($sdl3DllDir -ne "" -and (Test-Path "$sdl3DllDir\SDL3.dll")) {
    Copy-Item "$sdl3DllDir\SDL3.dll" "$ROOT\emu\Nt\SDL3.dll" -Force
    Write-Host "  Copied SDL3.dll to emu\Nt\" -ForegroundColor Green
}

# =============================================
# Build Summary
# =============================================
Write-Host ""
Write-Host "=== Build Summary ===" -ForegroundColor Cyan
Write-Host ""

$emuPath = "$ROOT\emu\Nt\o.emu.exe"
if (Test-Path $emuPath) {
    $size = (Get-Item $emuPath).Length / 1KB
    Write-Host "SUCCESS: SDL3 GUI Emulator built at $emuPath" -ForegroundColor Green
    Write-Host "  Size: $([math]::Round($size, 1)) KB"
    Write-Host ""
    Write-Host "To run:" -ForegroundColor Yellow
    Write-Host "  cd $ROOT"
    Write-Host "  .\emu\Nt\o.emu.exe -r . sh -l"
    Write-Host ""
    if (-not (Test-Path "$ROOT\emu\Nt\SDL3.dll")) {
        Write-Host "Note: SDL3.dll must be in PATH or next to o.emu.exe." -ForegroundColor Yellow
    }
} else {
    Write-Host "Emulator binary not found." -ForegroundColor Red
    Write-Host "Check build output above for errors."
}

Write-Host ""
