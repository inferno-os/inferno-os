#
# Package InferNode as a portable zip for Windows
#
# Creates a self-contained folder that users extract and double-click
# InferNode.exe to launch.  LLM service is handled by the native Limbo
# llmsrv inside the emulator — no external binary needed.
#
# Prerequisites:
#   - Run build-windows-sdl3.ps1 first (builds o.emu.exe + SDL3.dll)
#
# Usage:
#   .\package-windows-zip.ps1
#

$ErrorActionPreference = "Stop"

Write-Host "=== InferNode Windows Portable Package ===" -ForegroundColor Cyan
Write-Host ""

$ROOT = (Get-Location).Path
$StageDir = "$ROOT\InferNode"
$ZipPath = "$ROOT\InferNode-windows-amd64.zip"

# --- Verify build exists ---

$emuExe = "$ROOT\emu\Nt\o.emu.exe"
$sdl3Dll = "$ROOT\emu\Nt\SDL3.dll"
$launcher = "$ROOT\emu\Nt\InferNode.exe"

if (-not (Test-Path $emuExe)) {
    Write-Host "ERROR: o.emu.exe not found. Run build-windows-sdl3.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $sdl3Dll)) {
    Write-Host "ERROR: SDL3.dll not found next to o.emu.exe." -ForegroundColor Red
    exit 1
}

# --- Build launcher if needed ---

if (-not (Test-Path $launcher)) {
    Write-Host "Building InferNode.exe launcher..."
    $launcherScript = "$ROOT\emu\Nt\build-launcher.ps1"
    if (Test-Path $launcherScript) {
        & powershell -ExecutionPolicy Bypass -File $launcherScript
        if (-not (Test-Path $launcher)) {
            Write-Host "ERROR: Failed to build InferNode.exe launcher." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "ERROR: build-launcher.ps1 not found." -ForegroundColor Red
        exit 1
    }
}

# --- Create staging directory ---

if (Test-Path $StageDir) {
    Remove-Item -Recurse -Force $StageDir
}
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

Write-Host "Staging files..."

# --- Copy executables ---

Copy-Item $launcher "$StageDir\InferNode.exe"
Copy-Item $emuExe "$StageDir\o.emu.exe"
Copy-Item $sdl3Dll "$StageDir\SDL3.dll"

# --- Copy Inferno root filesystem ---

$rootDirs = @("dis", "lib", "fonts", "module", "services", "locale")
foreach ($d in $rootDirs) {
    $src = "$ROOT\$d"
    if (Test-Path $src) {
        # Use robocopy for speed, exclude .gitkeep and other git files
        & robocopy $src "$StageDir\$d" /E /NFL /NDL /NJH /NJS /NP /XF .gitkeep .gitignore | Out-Null
    }
}

# --- Copy icon if available ---

$ico = "$ROOT\Nt\Infernode.ico"
if (Test-Path $ico) {
    Copy-Item $ico "$StageDir\InferNode.ico"
}

# --- Summary of staged content ---

Write-Host ""
Write-Host "Staged contents:" -ForegroundColor Cyan
$totalSize = 0
Get-ChildItem -Path $StageDir -Recurse -File | ForEach-Object { $totalSize += $_.Length }

$exeSize = (Get-Item "$StageDir\InferNode.exe").Length / 1KB
$emuSize = (Get-Item "$StageDir\o.emu.exe").Length / 1KB
$sdlSize = (Get-Item "$StageDir\SDL3.dll").Length / 1KB
Write-Host "  InferNode.exe  $([math]::Round($exeSize, 0)) KB  (launcher)"
Write-Host "  o.emu.exe      $([math]::Round($emuSize, 0)) KB  (emulator)"
Write-Host "  SDL3.dll       $([math]::Round($sdlSize, 0)) KB  (graphics)"

foreach ($d in $rootDirs) {
    if (Test-Path "$StageDir\$d") {
        $dirSize = (Get-ChildItem -Path "$StageDir\$d" -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
        $count = (Get-ChildItem -Path "$StageDir\$d" -Recurse -File).Count
        Write-Host "  $d/  $([math]::Round($dirSize, 1)) MB  ($count files)"
    }
}

$totalMB = $totalSize / 1MB
Write-Host ""
Write-Host "  Total: $([math]::Round($totalMB, 1)) MB" -ForegroundColor Green

# --- Create zip ---

Write-Host ""
Write-Host "Creating zip archive..."

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath
}

Compress-Archive -Path $StageDir -DestinationPath $ZipPath -CompressionLevel Optimal

# --- Clean up ---

Remove-Item -Recurse -Force $StageDir

# --- Done ---

if (Test-Path $ZipPath) {
    $zipSize = (Get-Item $ZipPath).Length / 1MB
    Write-Host ""
    Write-Host "=== Package Complete ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $ZipPath" -ForegroundColor Green
    Write-Host "  Size: $([math]::Round($zipSize, 1)) MB"
    Write-Host ""
    Write-Host "To distribute:" -ForegroundColor Yellow
    Write-Host "  1. Share the zip file"
    Write-Host "  2. User extracts anywhere"
    Write-Host "  3. User double-clicks InferNode.exe"
} else {
    Write-Host "ERROR: Failed to create zip." -ForegroundColor Red
    exit 1
}

Write-Host ""
