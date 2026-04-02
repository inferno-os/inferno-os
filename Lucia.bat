@echo off
:: Launch Lucifer UI on Windows
:: Double-click this file from Explorer to start.
::
:: LLM service (local llmsrv or remote 9P mount) is configured in
:: lib/sh/profile and managed via the Settings app.

cd /d "%~dp0"

:: Launch Lucifer
"emu\Nt\o.emu.exe" -c1 -g 1280x800 -pheap=512m -pmain=512m -pimage=512m -r . sh /dis/lucifer-start.sh
