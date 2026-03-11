@echo off
:: Launch Lucifer UI on Windows
:: Double-click this file from Explorer to start.

cd /d "%~dp0"

:: Start llm9p if not running
tasklist /FI "IMAGENAME eq llm9p.exe" 2>NUL | find /I "llm9p.exe" >NUL
if errorlevel 1 (
    if exist "emu\Nt\llm9p.exe" (
        echo Starting llm9p server...
        start "" /B "emu\Nt\llm9p.exe" -backend cli -addr :5640
        timeout /t 1 /nobreak >NUL
    ) else (
        echo WARNING: llm9p.exe not found - AI features unavailable.
    )
) else (
    echo llm9p already running.
)

:: Launch Lucifer
"emu\Nt\o.emu.exe" -c1 -g 1280x800 -pheap=512m -pmain=512m -pimage=512m -r . sh /dis/lucifer-start.sh
