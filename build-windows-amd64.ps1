#
# Build script for Windows x86-64 (amd64) - Headless Emulator
# Run this from a Visual Studio Developer Command Prompt (x64).
#
# Prerequisites:
#   - MSVC (cl.exe, ml64.exe, link.exe, lib.exe) in PATH
#   - Run from project root directory
#
# Usage:
#   .\build-windows-amd64.ps1
#

$ErrorActionPreference = "Stop"

Write-Host "=== InferNode Windows x86-64 Build ===" -ForegroundColor Cyan
Write-Host ""

# Set up environment
$ROOT = (Get-Location).Path
$env:ROOT = $ROOT
$env:SYSHOST = "Nt"
$env:OBJTYPE = "amd64"
$env:SYSTARG = "Nt"

# Create output directories
$BinDir = "$ROOT\Nt\amd64\bin"
$LibDir = "$ROOT\Nt\amd64\lib"
$IncDir = "$ROOT\Nt\amd64\include"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $LibDir | Out-Null
New-Item -ItemType Directory -Force -Path $IncDir | Out-Null

Write-Host "ROOT=$ROOT"
Write-Host "SYSHOST=$env:SYSHOST"
Write-Host "OBJTYPE=$env:OBJTYPE"
Write-Host ""

# Check for required tools
Write-Host "Checking build requirements..." -ForegroundColor Yellow

$tools = @("cl.exe", "ml64.exe", "link.exe", "lib.exe")
foreach ($tool in $tools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: $tool not found. Run from a Visual Studio Developer Command Prompt (x64)." -ForegroundColor Red
        Write-Host "  Example: Open 'x64 Native Tools Command Prompt for VS 2022'"
        exit 1
    }
}
Write-Host "Build tools found." -ForegroundColor Green
Write-Host ""

# Common compiler flags
$CFLAGS = @(
    "/nologo", "/c", "/O2", "/Gy", "/GF", "/MT",
    "/W3", "/wd4018", "/wd4244", "/wd4245", "/wd4068",
    "/wd4090", "/wd4554", "/wd4146", "/wd4996", "/wd4305",
    "/wd4102", "/wd4761",
    "/D_AMD64_", "/DWINDOWS_AMD64",
    "/I$ROOT\Nt\amd64\include",
    "/I$ROOT\include",
    "/I$ROOT\utils\include"
)

# Helper function to compile C files
function Compile-CFiles {
    param(
        [string]$Dir,
        [string[]]$Sources,
        [string[]]$ExtraFlags = @()
    )
    $flags = $CFLAGS + $ExtraFlags
    foreach ($src in $Sources) {
        $srcPath = Join-Path $Dir $src
        if (Test-Path $srcPath) {
            Write-Host "  Compiling $src..."
            & cl.exe @flags $srcPath
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: Failed to compile $src" -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "  WARNING: $src not found, skipping" -ForegroundColor Yellow
        }
    }
}

# Helper function to create static library
function Create-Library {
    param(
        [string]$Name,
        [string]$OutputDir
    )
    $objs = Get-ChildItem -Path "." -Filter "*.obj" | ForEach-Object { $_.Name }
    if ($objs.Count -eq 0) {
        Write-Host "  WARNING: No object files for $Name" -ForegroundColor Yellow
        return
    }
    & lib.exe /nologo "/OUT:$OutputDir\$Name" @objs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create $Name" -ForegroundColor Red
        exit 1
    }
    Write-Host "  $Name built" -ForegroundColor Green
}

# =============================================
# Build libregexp
# =============================================
Write-Host "=== Building libregexp ===" -ForegroundColor Cyan
Push-Location "$ROOT\utils\libregexp"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$regexpSrc = @(
    "regcomp.c", "regerror.c", "regexec.c", "regsub.c",
    "regaux.c", "rregexec.c", "rregsub.c"
)
Compile-CFiles -Dir "." -Sources $regexpSrc
Create-Library -Name "libregexp.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build lib9
# =============================================
Write-Host "=== Building lib9 ===" -ForegroundColor Cyan
Push-Location "$ROOT\lib9"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$commonSrc = @(
    "convD2M.c", "convM2D.c", "convM2S.c", "convS2M.c",
    "fcallfmt.c", "qsort.c", "runestrlen.c", "strtoll.c", "rune.c"
)

$importSrc = @(
    "argv0.c", "charstod.c", "cistrcmp.c", "cistrncmp.c", "cistrstr.c",
    "cleanname.c", "create.c",
    "dofmt.c", "dorfmt.c", "errfmt.c", "exits.c", "fmt.c", "fmtfd.c",
    "fmtlock.c", "fmtprint.c", "fmtquote.c", "fmtrune.c", "fmtstr.c",
    "fmtvprint.c", "fprint.c", "getfields.c",
    "nulldir.c", "pow10.c", "print.c", "readn.c", "rerrstr.c",
    "runeseprint.c", "runesmprint.c", "runesnprint.c", "runevseprint.c",
    "seprint.c", "smprint.c", "snprint.c", "sprint.c",
    "strdup.c", "strecpy.c", "sysfatal.c", "tokenize.c",
    "u16.c", "u32.c", "u64.c",
    "utflen.c", "utfnlen.c", "utfrrune.c", "utfrune.c", "utfecpy.c",
    "vfprint.c", "vseprint.c", "vsmprint.c", "vsnprint.c"
)

$ntSrc = @(
    "dirstat-Nt.c", "errstr-Nt.c", "getuser-Nt.c",
    "getwd-Nt.c", "setbinmode-Nt.c", "lock-Nt-amd64.c"
)

# Extra sources
$extraSrc = @("seek.c", "isnan-posix.c")

$allSrc = $commonSrc + $importSrc + $ntSrc + $extraSrc
Compile-CFiles -Dir "." -Sources $allSrc
Create-Library -Name "lib9.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build libbio
# =============================================
Write-Host "=== Building libbio ===" -ForegroundColor Cyan
Push-Location "$ROOT\libbio"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$bioSrc = @(
    "bbuffered.c", "bfildes.c", "bflush.c", "bgetrune.c", "bgetc.c",
    "bgetd.c", "binit.c", "boffset.c", "bprint.c", "bputrune.c",
    "bputc.c", "brdline.c", "brdstr.c", "bread.c", "bseek.c",
    "bvprint.c", "bwrite.c"
)
Compile-CFiles -Dir "." -Sources $bioSrc
Create-Library -Name "libbio.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build mk (Plan 9 build tool for Windows)
# =============================================
Write-Host "=== Building mk ===" -ForegroundColor Cyan
Push-Location "$ROOT\utils\mk"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$mkCommon = @(
    "arc.c", "archive.c", "bufblock.c", "env.c", "file.c",
    "graph.c", "job.c", "lex.c", "main.c", "match.c",
    "mk.c", "parse.c", "recipe.c", "rule.c", "run.c",
    "shprint.c", "symtab.c", "var.c", "varsub.c", "word.c"
)
# Use Nt.c (Windows model) and sh.c (shell type)
$mkPlatform = @("Nt.c", "sh.c")

# Write ROOT to a header file to avoid command-line quoting issues
$rootFwd = $ROOT -replace '\\','/'
$rootH = '#define ROOT "' + $rootFwd + '"'
$rootH | Set-Content -Path "$ROOT\utils\mk\rootpath.h" -Encoding ASCII
$mkFlags = @("/FI$ROOT\utils\mk\rootpath.h")
Compile-CFiles -Dir "." -Sources ($mkCommon + $mkPlatform) -ExtraFlags $mkFlags

# Link mk
$mkObjs = Get-ChildItem -Path "." -Filter "*.obj" | ForEach-Object { $_.Name }
& link.exe /nologo "/OUT:$BinDir\mk.exe" @mkObjs `
    "$LibDir\libregexp.lib" "$LibDir\libbio.lib" "$LibDir\lib9.lib" `
    advapi32.lib
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to link mk.exe" -ForegroundColor Red
    exit 1
}
Write-Host "  mk.exe built" -ForegroundColor Green
Pop-Location

Write-Host ""
Write-Host "=== Bootstrap Complete ===" -ForegroundColor Green
Write-Host "mk is available at: $BinDir\mk.exe"
Write-Host ""

# =============================================
# Build remaining libraries with mk
# =============================================
Write-Host "=== Building Libraries with mk ===" -ForegroundColor Cyan

# For mk-based builds, we need the mkconfig and mkfiles to work on Windows.
# Since the mk tool uses SHELLTYPE=sh, we need a Windows-compatible setup.
# For now, build the remaining libraries directly with MSVC.

# =============================================
# Build libmp (explicit source list from mkfile)
# =============================================
Write-Host "Building libmp..." -ForegroundColor Yellow
Push-Location "$ROOT\libmp"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$mpSrc = @(
    "mpaux.c", "mpfmt.c", "strtomp.c", "mptobe.c", "mptole.c",
    "betomp.c", "letomp.c", "mpadd.c", "mpsub.c", "mpcmp.c",
    "mpfactorial.c", "mpmul.c", "mpleft.c", "mpright.c",
    "mpvecadd.c", "mpvecsub.c", "mpvecdigmuladd.c", "mpveccmp.c",
    "mpdigdiv.c", "mpdiv.c", "mpexp.c", "mpmod.c",
    "mpextendedgcd.c", "mpinvert.c", "mprand.c", "crt.c",
    "mptoi.c", "mptoui.c", "mptov.c", "mptouv.c"
)
$mpFlags = @("/I$ROOT\libmp", "/I$ROOT\include", "/I$ROOT\Nt\amd64\include")
Compile-CFiles -Dir "." -Sources $mpSrc -ExtraFlags $mpFlags
Create-Library -Name "libmp.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build libsec (explicit source list from mkfile)
# =============================================
Write-Host "Building libsec..." -ForegroundColor Yellow
Push-Location "$ROOT\libsec"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$secSrc = @(
    "des.c", "desmodes.c", "desECB.c", "desCBC.c", "des3ECB.c", "des3CBC.c",
    "aes.c", "aesctr.c", "aesgcm.c", "blowfish.c",
    "chacha.c", "poly1305.c", "ccpoly.c",
    "x25519.c", "ecc.c",
    "idea.c",
    "hmac.c", "md5.c", "md5block.c", "md4.c", "sha1.c", "sha1block.c",
    "sha2.c", "sha256block.c", "sha512block.c",
    "sha1pickle.c", "md5pickle.c", "rc4.c",
    "genrandom.c", "prng.c", "fastrand.c", "nfastrand.c",
    "probably_prime.c", "smallprimetest.c", "genprime.c", "dsaprimes.c",
    "gensafeprime.c", "genstrongprime.c", "dhparams.c",
    "rsagen.c", "rsafill.c", "rsaencrypt.c", "rsadecrypt.c", "rsaalloc.c", "rsaprivtopub.c",
    "eggen.c", "egencrypt.c", "egdecrypt.c", "egalloc.c", "egprivtopub.c",
    "egsign.c", "egverify.c",
    "dsagen.c", "dsaalloc.c", "dsaprivtopub.c", "dsasign.c", "dsaverify.c"
)
$secFlags = @("/I$ROOT\libsec", "/I$ROOT\libmp", "/I$ROOT\include", "/I$ROOT\Nt\amd64\include")
Compile-CFiles -Dir "." -Sources $secSrc -ExtraFlags $secFlags
Create-Library -Name "libsec.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build libmath (root + fdlibm/, FPcontrol-Nt)
# =============================================
Write-Host "Building libmath..." -ForegroundColor Yellow
Push-Location "$ROOT\libmath"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$mathRootSrc = @(
    "blas.c", "dtoa.c", "fdim.c", "FPcontrol-Nt.c",
    "gemm.c", "g_fmt.c", "gfltconv.c", "pow10.c"
)
$mathFdlibmSrc = @(
    "e_acos.c", "e_acosh.c", "e_asin.c", "e_atan2.c", "e_atanh.c",
    "e_cosh.c", "e_exp.c", "e_fmod.c", "e_hypot.c",
    "e_j0.c", "e_j1.c", "e_jn.c", "e_lgamma_r.c",
    "e_log.c", "e_log10.c", "e_pow.c", "e_rem_pio2.c",
    "e_remainder.c", "e_sinh.c", "e_sqrt.c",
    "k_cos.c", "k_rem_pio2.c", "k_sin.c", "k_tan.c",
    "s_asinh.c", "s_atan.c", "s_cbrt.c", "s_ceil.c", "s_copysign.c",
    "s_cos.c", "s_erf.c", "s_expm1.c", "s_fabs.c", "s_finite.c",
    "s_floor.c", "s_ilogb.c", "s_log1p.c",
    "s_nextafter.c", "s_rint.c", "s_scalbn.c",
    "s_sin.c", "s_tan.c", "s_tanh.c"
)
$mathFlags = @("/I$ROOT\libmath", "/I$ROOT\libmath\fdlibm", "/I$ROOT\include", "/I$ROOT\Nt\amd64\include", "/wd4273")
Compile-CFiles -Dir "." -Sources $mathRootSrc -ExtraFlags $mathFlags
# fdlibm provides its own math implementations - disable MSVC intrinsics and suppress dll linkage warnings
$fdlibmFlags = $mathFlags + @("/Oi-", "/wd4273")
Compile-CFiles -Dir "fdlibm" -Sources $mathFdlibmSrc -ExtraFlags $fdlibmFlags
Create-Library -Name "libmath.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build libmemdraw (explicit source list from mkfile)
# =============================================
Write-Host "Building libmemdraw..." -ForegroundColor Yellow
Push-Location "$ROOT\libmemdraw"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$mdSrc = @(
    "arc.c", "cmap.c", "cread.c", "defont.c", "ellipse.c", "fillpoly.c",
    "hwdraw.c", "icossin.c", "icossin2.c", "iprint.c", "line.c",
    "openmemsubfont.c", "poly.c", "read.c", "string.c", "subfont.c", "write.c",
    "alloc.c", "cload.c", "draw.c", "load.c", "unload.c"
)
$mdFlags = @("/I$ROOT\libmemdraw", "/I$ROOT\include", "/I$ROOT\Nt\amd64\include")
Compile-CFiles -Dir "." -Sources $mdSrc -ExtraFlags $mdFlags
Create-Library -Name "libmemdraw.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build libmemlayer (explicit source list from mkfile)
# =============================================
Write-Host "Building libmemlayer..." -ForegroundColor Yellow
Push-Location "$ROOT\libmemlayer"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$mlSrc = @(
    "draw.c", "layerop.c", "ldelete.c", "lhide.c", "line.c", "load.c",
    "lorigin.c", "lsetrefresh.c", "ltofront.c", "ltorear.c", "unload.c",
    "lalloc.c"
)
$mlFlags = @("/I$ROOT\libmemlayer", "/I$ROOT\include", "/I$ROOT\Nt\amd64\include")
Compile-CFiles -Dir "." -Sources $mlSrc -ExtraFlags $mlFlags
Create-Library -Name "libmemlayer.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build libdraw (explicit source list from mkfile)
# =============================================
Write-Host "Building libdraw..." -ForegroundColor Yellow
Push-Location "$ROOT\libdraw"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$drawSrc = @(
    "alloc.c", "allocimagemix.c", "arith.c", "bezier.c", "border.c",
    "buildfont.c", "bytesperline.c", "chan.c", "cloadimage.c", "computil.c",
    "creadimage.c", "defont.c", "draw.c", "drawrepl.c", "ellipse.c",
    "font.c", "freesubfont.c", "getdefont.c", "getsubfont.c", "init.c",
    "line.c", "mkfont.c", "openfont.c", "poly.c", "loadimage.c",
    "readimage.c", "readsubfont.c", "rectclip.c", "replclipr.c", "rgb.c",
    "string.c", "stringbg.c", "stringsubfont.c", "stringwidth.c",
    "subfont.c", "subfontcache.c", "subfontname.c", "unloadimage.c",
    "window.c", "writecolmap.c", "writeimage.c", "writesubfont.c"
)
$drawFlags = @("/I$ROOT\libdraw", "/I$ROOT\include", "/I$ROOT\Nt\amd64\include")
Compile-CFiles -Dir "." -Sources $drawSrc -ExtraFlags $drawFlags
Create-Library -Name "libdraw.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build limbo compiler (explicit source list from mkfile)
# =============================================
Write-Host ""
Write-Host "=== Building Limbo Compiler ===" -ForegroundColor Cyan
Push-Location "$ROOT\limbo"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

# Generate y.tab.c and y.tab.h from limbo.y if needed
if (-not (Test-Path "y.tab.c") -or -not (Test-Path "y.tab.h")) {
    $bison = Get-ChildItem -Recurse -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter "win_bison.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bison) {
        Write-Host "  Generating y.tab.c/h from limbo.y..."
        & $bison.FullName -d -o y.tab.c limbo.y
    } else {
        Write-Host "ERROR: y.tab.c/h missing and win_bison not found. Install: winget install WinFlexBison.win_flex_bison" -ForegroundColor Red
        exit 1
    }
}

$limboSrc = @(
    "asm.c", "com.c", "decls.c", "dis.c", "dtocanon.c", "ecom.c",
    "gen.c", "lex.c", "nodes.c", "optab.c", "optim.c", "sbl.c",
    "stubs.c", "typecheck.c", "types.c", "y.tab.c"
)
# Write INCPATH to header file to avoid quoting issues
$incPathFwd = ($ROOT -replace '\\','/') + "/module"
$incPathH = '#define INCPATH "' + $incPathFwd + '"'
$incPathH | Set-Content -Path "$ROOT\limbo\incpath.h" -Encoding ASCII
$limboFlags = @("/I$ROOT\limbo", "/I$ROOT\include", "/I$ROOT\Nt\amd64\include", "/FI$ROOT\limbo\incpath.h")
Compile-CFiles -Dir "." -Sources $limboSrc -ExtraFlags $limboFlags

$limboObjs = Get-ChildItem -Path "." -Filter "*.obj" | ForEach-Object { $_.Name }
& link.exe /nologo "/OUT:$BinDir\limbo.exe" @limboObjs `
    "$LibDir\libbio.lib" "$LibDir\libmath.lib" "$LibDir\libsec.lib" `
    "$LibDir\libmp.lib" "$LibDir\lib9.lib" `
    advapi32.lib
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to link limbo.exe" -ForegroundColor Red
    exit 1
}
Write-Host "  limbo.exe built" -ForegroundColor Green
Pop-Location

# Verify limbo was built
if (-not (Test-Path "$BinDir\limbo.exe")) {
    Write-Host "ERROR: limbo compiler not built!" -ForegroundColor Red
    exit 1
}

# =============================================
# Build libinterp (interpreter + AMD64 JIT compiler)
# =============================================
Write-Host ""
Write-Host "=== Building libinterp ===" -ForegroundColor Cyan
Push-Location "$ROOT\libinterp"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

# Generate required headers using the limbo compiler
$LIMBO = "$BinDir\limbo.exe"
Write-Host "  Generating runtime headers..."
& $LIMBO -a -I "$ROOT\module" "$ROOT\module\runt.m" 2>$null | Set-Content -Path "runt.h" -Encoding ASCII
& $LIMBO -t Sys -I "$ROOT\module" "$ROOT\module\runt.m" 2>$null | Set-Content -Path "sysmod.h" -Encoding ASCII
& $LIMBO -t Draw -I "$ROOT\module" "$ROOT\module\runt.m" 2>$null | Set-Content -Path "drawmod.h" -Encoding ASCII
& $LIMBO -t Math -I "$ROOT\module" "$ROOT\module\runt.m" 2>$null | Set-Content -Path "mathmod.h" -Encoding ASCII
& $LIMBO -t Keyring -I "$ROOT\module" "keyringif.m" 2>$null | Set-Content -Path "keyring.h" -Encoding ASCII
& $LIMBO -a -I "$ROOT\module" "keyringif.m" 2>$null | Set-Content -Path "keyringif.h" -Encoding ASCII
& $LIMBO -t Loader -I "$ROOT\module" "$ROOT\module\runt.m" 2>$null | Set-Content -Path "loadermod.h" -Encoding ASCII
& $LIMBO -t IPints -I "$ROOT\module" "$ROOT\module\ipints.m" 2>$null | Set-Content -Path "ipintsmod.h" -Encoding ASCII
& $LIMBO -t Crypt -I "$ROOT\module" "$ROOT\module\runt.m" 2>$null | Set-Content -Path "cryptmod.h" -Encoding ASCII
& $LIMBO -t Tk -I "$ROOT\module" "$ROOT\module\runt.m" 2>$null | Set-Content -Path "tkmod.h" -Encoding ASCII

$interpSrc = @(
    "alt.c", "conv.c", "crypt.c", "dec.c", "draw.c", "gc.c", "geom.c",
    "heap.c", "heapaudit.c", "ipint.c", "link.c", "load.c", "math.c",
    "raise.c", "readmod.c", "runt.c", "sign.c", "stack.c", "tk.c",
    "validstk.c", "xec.c", "das-amd64.c", "comp-amd64.c", "keyring.c", "string.c",
    "gpu-stub.c"
)
$interpFlags = @(
    "/DEMU", "/I.", "/I$ROOT\include",
    "/I$ROOT\Nt\amd64\include", "/I$ROOT\libinterp"
)
Compile-CFiles -Dir "." -Sources $interpSrc -ExtraFlags $interpFlags
Create-Library -Name "libinterp.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build libkeyring
# =============================================
Write-Host "Building libkeyring..." -ForegroundColor Yellow
Push-Location "$ROOT\libkeyring"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$krSrc = Get-ChildItem -Path "." -Filter "*.c" | ForEach-Object { $_.Name }
$krFlags = @(
    "/DEMU", "/I.", "/I$ROOT\include",
    "/I$ROOT\Nt\amd64\include", "/I$ROOT\libinterp",
    "/I$ROOT\libsec", "/I$ROOT\libmp"
)
Compile-CFiles -Dir "." -Sources $krSrc -ExtraFlags $krFlags
Create-Library -Name "libkeyring.lib" -OutputDir $LibDir
Pop-Location

# =============================================
# Build Headless Emulator
# =============================================
Write-Host ""
Write-Host "=== Building Headless Emulator ===" -ForegroundColor Cyan
Push-Location "$ROOT\emu\Nt"
Remove-Item -Force *.obj -ErrorAction SilentlyContinue

$emuCFlags = @(
    "/nologo", "/c", "/O2", "/Gy", "/GF", "/MT",
    "/W3", "/wd4018", "/wd4244", "/wd4245", "/wd4068",
    "/wd4090", "/wd4554", "/wd4146", "/wd4996", "/wd4305",
    "/wd4102", "/wd4761",
    "/DEMU", "/D_AMD64_", "/DWINDOWS_AMD64",
    "/I.", "/I..\port",
    "/I$ROOT\Nt\amd64\include",
    "/I$ROOT\include",
    "/I$ROOT\libinterp"
)

# Platform-specific source files (from emu/Nt/)
Write-Host "  Compiling platform sources..."
$ntSources = @(
    "os.c", "cmd.c", "no_win.c", "fp.c",
    "stubs-headless.c",
    "devfs.c",
    "ipif6.c"
)
foreach ($src in $ntSources) {
    if (Test-Path $src) {
        Write-Host "    $src"
        & cl.exe @emuCFlags $src
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Failed to compile $src" -ForegroundColor Yellow
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

# Port source files (from emu/port/)
Write-Host "  Compiling port sources..."
$portSources = @(
    "alloc.c", "cache.c", "chan.c", "dev.c", "devtab.c", "dial.c",
    "dis.c", "discall.c", "env.c", "error.c", "errstr.c",
    "exception.c", "exportfs.c", "inferno.c", "latin1.c",
    "main.c", "parse.c", "pgrp.c", "print.c", "proc.c",
    "qio.c", "random.c", "sysfile.c", "uqid.c",
    "lock.c",
    "devcons.c", "devdup.c", "devenv.c", "devip.c",
    "devmnt.c", "devpipe.c", "devprog.c", "devroot.c",
    "devsrv.c", "devssl.c", "devcmd.c",
    "ipaux.c", "srv.c"
)
foreach ($src in $portSources) {
    $srcPath = "..\port\$src"
    if (Test-Path $srcPath) {
        Write-Host "    port/$src"
        & cl.exe @emuCFlags $srcPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Failed to compile port/$src" -ForegroundColor Yellow
        }
    }
}

# Generate config .c file for headless build
# This is equivalent to what mkdevlist generates
Write-Host "  Generating emu-headless config..."
$configC = @"
#include "dat.h"
#include "fns.h"
#include "error.h"
#include "interp.h"

/*
 * Root filesystem tables.
 * Generated from emu-headless config root section:
 *   /dev /fd /prog /net /chan /env
 * All are empty directories under /.
 *
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
	0,	&roottab[1],	6,	nil,	/* / -> children are qids 1-6 */
	0,	nil,	0,	nil,	/* dev */
	0,	nil,	0,	nil,	/* fd */
	0,	nil,	0,	nil,	/* prog */
	0,	nil,	0,	nil,	/* net */
	0,	nil,	0,	nil,	/* chan */
	0,	nil,	0,	nil,	/* env */
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
extern Dev ipdevtab;

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
	&ipdevtab,
	nil,
};

void links(void){
}

extern void sysmodinit(void);
extern void mathmodinit(void);
extern void srvmodinit(void);
extern void keyringmodinit(void);
extern void cryptmodinit(void);
extern void ipintsmodinit(void);
void modinit(void){
	sysmodinit();
	mathmodinit();
	srvmodinit();
	keyringmodinit();
	cryptmodinit();
	ipintsmodinit();
}

char* conffile = "emu-headless";
ulong kerndate = 0;
"@
$configC | Set-Content -Path "emu-config.c" -Encoding ASCII
& cl.exe @emuCFlags "emu-config.c"

# Link the emulator
Write-Host "  Linking o.emu.exe..."
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
    ws2_32.lib user32.lib gdi32.lib advapi32.lib winmm.lib mpr.lib kernel32.lib
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to link o.emu.exe" -ForegroundColor Red
    exit 1
}
Write-Host "  o.emu.exe built" -ForegroundColor Green
Pop-Location

# =============================================
# Build Dis bytecode
# =============================================
Write-Host ""
Write-Host "=== Building Dis Bytecode ===" -ForegroundColor Cyan

$LIMBO = "$BinDir\limbo.exe"
$MODULE = "$ROOT\module"

# Helper: compile all .b files in a source dir to a target dis dir.
# Compiles to a temp file first to avoid clobbering existing .dis on failure.
function Build-DisDir {
    param(
        [string]$SrcDir,
        [string]$DisDir
    )
    if (-not (Test-Path $SrcDir)) { return 0 }
    New-Item -ItemType Directory -Force -Path $DisDir | Out-Null
    $count = 0
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    Get-ChildItem -Path $SrcDir -Filter "*.b" -File | ForEach-Object {
        $name = $_.BaseName
        $tmpDis = "$DisDir\$name.dis.tmp"
        $output = & $LIMBO -I $MODULE -o $tmpDis $_.FullName 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpDis)) {
            Move-Item -Force $tmpDis "$DisDir\$name.dis"
            $count++
        } else {
            Remove-Item -Force $tmpDis -ErrorAction SilentlyContinue
        }
    }
    $ErrorActionPreference = $prevPref
    return $count
}

$totalDis = 0

# appl/cmd/*.b -> dis/
Write-Host "  Building commands..."
$n = Build-DisDir "$ROOT\appl\cmd" "$ROOT\dis"
$totalDis += $n

# appl/cmd/<subdir>/*.b -> dis/<subdir>/
$cmdSubdirs = @("auth","auxi","dbm","dict","disk","fs","install","ip","ndb","sh")
foreach ($sub in $cmdSubdirs) {
    $n = Build-DisDir "$ROOT\appl\cmd\$sub" "$ROOT\dis\$sub"
    $totalDis += $n
}

# appl/lib/*.b -> dis/lib/
Write-Host "  Building libraries..."
$n = Build-DisDir "$ROOT\appl\lib" "$ROOT\dis\lib"
$totalDis += $n

# Other top-level appl dirs -> dis/<name>/
$applDirs = @("acme","charon","grid","math","svc","veltro","wm","xenith")
foreach ($dir in $applDirs) {
    $n = Build-DisDir "$ROOT\appl\$dir" "$ROOT\dis\$dir"
    $totalDis += $n
}

Write-Host "  Built $totalDis .dis files" -ForegroundColor Green

# =============================================
# Build Summary
# =============================================
Write-Host ""
Write-Host "=== Build Summary ===" -ForegroundColor Cyan
Write-Host ""

$emuPath = "$ROOT\emu\Nt\o.emu.exe"
if (Test-Path $emuPath) {
    $size = (Get-Item $emuPath).Length / 1KB
    Write-Host "SUCCESS: Emulator built at $emuPath" -ForegroundColor Green
    Write-Host "  Size: $([math]::Round($size, 1)) KB"
    Write-Host ""
    Write-Host "To run:" -ForegroundColor Yellow
    Write-Host "  cd $ROOT"
    Write-Host "  .\emu\Nt\o.emu.exe -r ."
} else {
    Write-Host "Emulator binary not found." -ForegroundColor Red
    Write-Host "Check build output above for errors."
}

if (Test-Path "$BinDir\limbo.exe") {
    Write-Host ""
    Write-Host "Limbo compiler: $BinDir\limbo.exe" -ForegroundColor Green
}
if (Test-Path "$BinDir\mk.exe") {
    Write-Host "mk build tool:  $BinDir\mk.exe" -ForegroundColor Green
}

Write-Host ""
