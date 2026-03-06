#
# Package InferNode as MSIX for Windows
#
# Prerequisites:
#   - Windows 10 SDK (makeappx.exe, signtool.exe)
#   - Infernode.exe built (run build-windows-sdl3.ps1 first)
#   - SDL3.dll available
#
# Usage:
#   .\package-windows-msix.ps1
#   .\package-windows-msix.ps1 -Sign -CertPath "cert.pfx" -CertPassword "password"
#

param(
    [switch]$Sign,
    [string]$CertPath = "",
    [string]$CertPassword = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== InferNode MSIX Packaging ===" -ForegroundColor Cyan
Write-Host ""

$ROOT = (Get-Location).Path

# Verify build exists
$emuGui = "$ROOT\emu\Nt\Infernode.exe"
if (-not (Test-Path $emuGui)) {
    Write-Host "ERROR: Infernode.exe not found. Run build-windows-sdl3.ps1 first." -ForegroundColor Red
    exit 1
}

# Find Windows SDK tools
$sdkPaths = @(
    "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64",
    "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22000.0\x64",
    "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64"
)

$makeappx = ""
foreach ($sp in $sdkPaths) {
    if (Test-Path "$sp\makeappx.exe") {
        $makeappx = "$sp\makeappx.exe"
        break
    }
}

if ($makeappx -eq "") {
    # Try to find via PATH
    $makeappx = (Get-Command makeappx.exe -ErrorAction SilentlyContinue).Source
}

if (-not $makeappx -or -not (Test-Path $makeappx)) {
    Write-Host "ERROR: makeappx.exe not found. Install the Windows 10 SDK." -ForegroundColor Red
    exit 1
}
Write-Host "Using: $makeappx" -ForegroundColor Green

# Create staging directory
$stageDir = "$ROOT\msix-stage"
if (Test-Path $stageDir) {
    Remove-Item -Recurse -Force $stageDir
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
New-Item -ItemType Directory -Force -Path "$stageDir\Assets" | Out-Null

# Copy manifest
Copy-Item "$ROOT\Nt\Infernode.appxmanifest" "$stageDir\AppxManifest.xml"

# Copy executable
Copy-Item $emuGui "$stageDir\"

# Copy headless emu too
$emuHeadless = "$ROOT\emu\Nt\emu-headless.exe"
if (Test-Path $emuHeadless) {
    Copy-Item $emuHeadless "$stageDir\"
}

# Copy SDL3.dll if found
$sdl3Dll = ""
$sdl3Paths = @(
    "$ROOT\emu\Nt\SDL3.dll",
    "C:\vcpkg\installed\x64-windows\bin\SDL3.dll",
    "$env:SDL3DIR\bin\SDL3.dll"
)
foreach ($sp in $sdl3Paths) {
    if ($sp -and (Test-Path $sp)) {
        $sdl3Dll = $sp
        break
    }
}
if ($sdl3Dll -ne "") {
    Copy-Item $sdl3Dll "$stageDir\"
    Write-Host "Included SDL3.dll" -ForegroundColor Green
} else {
    Write-Host "WARNING: SDL3.dll not found - package will need it at runtime" -ForegroundColor Yellow
}

# Copy Inferno root filesystem
Write-Host "Copying Inferno root filesystem..."
$rootDirs = @("dis", "lib", "fonts", "module", "services", "locale")
foreach ($d in $rootDirs) {
    $src = "$ROOT\$d"
    if (Test-Path $src) {
        Copy-Item -Recurse $src "$stageDir\$d"
    }
}

# Generate placeholder asset PNGs
# In a real build, these would be generated from Infernode.ico
Write-Host "Generating placeholder assets..."

# Create minimal 1x1 PNG (transparent) as placeholders
# Real assets should be generated from the .ico file
$pngHeader = [byte[]]@(
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  # PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  # IHDR chunk
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,  # 1x1 pixels
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,  # RGBA, deflate
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,  # IDAT chunk
    0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,  # compressed data
    0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,  #
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,  # IEND chunk
    0x60, 0x82
)

$assetNames = @("StoreLogo.png", "Square44x44Logo.png", "Square150x150Logo.png", "Wide310x150Logo.png")
foreach ($asset in $assetNames) {
    [System.IO.File]::WriteAllBytes("$stageDir\Assets\$asset", $pngHeader)
}

Write-Host "NOTE: Replace Assets\*.png with real icons generated from Nt\Infernode.ico" -ForegroundColor Yellow

# Copy icon if exists
if (Test-Path "$ROOT\Nt\Infernode.ico") {
    Copy-Item "$ROOT\Nt\Infernode.ico" "$stageDir\"
}

# Create MSIX package
$msixPath = "$ROOT\Infernode.msix"
Write-Host ""
Write-Host "Creating MSIX package..."
& $makeappx pack /d $stageDir /p $msixPath /o
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create MSIX package" -ForegroundColor Red
    exit 1
}

# Sign if requested
if ($Sign -and $CertPath -ne "") {
    $signtoolDir = Split-Path $makeappx
    $signtool = "$signtoolDir\signtool.exe"
    if (Test-Path $signtool) {
        Write-Host "Signing package..."
        if ($CertPassword -ne "") {
            & $signtool sign /f $CertPath /p $CertPassword /fd SHA256 $msixPath
        } else {
            & $signtool sign /f $CertPath /fd SHA256 $msixPath
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Signing failed" -ForegroundColor Yellow
        } else {
            Write-Host "Package signed successfully" -ForegroundColor Green
        }
    } else {
        Write-Host "WARNING: signtool.exe not found, skipping signing" -ForegroundColor Yellow
    }
}

# Clean up staging directory
Remove-Item -Recurse -Force $stageDir

# Summary
Write-Host ""
Write-Host "=== Packaging Complete ===" -ForegroundColor Cyan
if (Test-Path $msixPath) {
    $size = (Get-Item $msixPath).Length / 1MB
    Write-Host "MSIX package: $msixPath" -ForegroundColor Green
    Write-Host "Size: $([math]::Round($size, 1)) MB"
    Write-Host ""
    Write-Host "To sideload:" -ForegroundColor Yellow
    Write-Host "  1. Enable Developer Mode in Windows Settings"
    Write-Host "  2. Double-click $msixPath"
    Write-Host "  3. Or: Add-AppPackage -Path $msixPath"
} else {
    Write-Host "MSIX package not created." -ForegroundColor Red
}

Write-Host ""
