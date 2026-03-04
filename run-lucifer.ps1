#
# Launch Lucifer UI on Windows
# Run from the project root directory.
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

& $EMU -g $geometry -pheap=512m -pmain=512m -pimage=512m -r . sh -l -c 'luciuisrv; echo activity create Main > /n/ui/ctl; /dis/veltro/tools9p -m /tool -p /dis/wm read list find search grep write edit exec launch spawn xenith ask diff json http git memory todo websearch mail present; lucibridge &; lucifer'
