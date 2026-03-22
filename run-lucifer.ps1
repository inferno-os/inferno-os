#
# Launch Lucifer UI on Windows
# Run from the project root directory.
#
# LLM service (local llmsrv or remote 9P mount) is configured in
# lib/sh/profile and managed via the Settings app.
#
# Usage:
#   .\run-lucifer.ps1
#   .\run-lucifer.ps1 -Width 1920 -Height 1080
#

param(
    [int]$Width = 1280,
    [int]$Height = 800
)

$ROOT = (Get-Location).Path
$EMU = "$ROOT\emu\Nt\o.emu.exe"

if (-not (Test-Path $EMU)) {
    Write-Host "ERROR: o.emu.exe not found. Build with build-windows-sdl3.ps1 first." -ForegroundColor Red
    exit 1
}

$geometry = "${Width}x${Height}"

& $EMU -c1 -g $geometry -pheap=512m -pmain=512m -pimage=512m -r . sh -l /dis/lucifer-start.sh
