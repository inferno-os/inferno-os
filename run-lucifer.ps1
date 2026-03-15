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
$LLM9P = "$ROOT\emu\Nt\llm9p.exe"

if (-not (Test-Path $EMU)) {
    Write-Host "ERROR: o.emu.exe not found. Build with build-windows-sdl3.ps1 first." -ForegroundColor Red
    exit 1
}

$geometry = "${Width}x${Height}"

# Start llm9p inference server if not already running
$llm9pRunning = Get-Process -Name "llm9p" -ErrorAction SilentlyContinue
if (-not $llm9pRunning) {
    if (Test-Path $LLM9P) {
        Write-Host "Starting llm9p server..."
        Start-Process -FilePath $LLM9P -ArgumentList "-backend","cli","-addr",":5640" -WindowStyle Hidden
        Start-Sleep -Seconds 1
    } else {
        Write-Host "WARNING: llm9p.exe not found - AI features will be unavailable." -ForegroundColor Yellow
    }
} else {
    Write-Host "llm9p already running."
}

# Default tool set: non-destructive tools enabled out of the box.
# Potentially destructive tools (exec, launch, spawn, git, mail) are registered
# in tools9p but NOT active by default — enable them via the context zone.
# The startup script handles tool registration, MA bridge, and task dashboard.
#
# The llm9p mount is done here (not in profile) because the Nt emu's TCP
# stack crashes on DNS lookups for unknown hostnames like 'llmserver'.
# PowerShell preserves single quotes inside double quotes, so the Inferno
# shell receives 'tcp!127.0.0.1!5640' correctly.
& $EMU -c1 -g $geometry -pheap=512m -pmain=512m -pimage=512m -r . sh /dis/lucifer-start.sh
