#!/bin/sh
# Launch Lucifer UI with Veltro agent bridge
# Run from anywhere: sh /path/to/run-lucifer.sh
ROOT=/Users/pdfinn/github.com/NERVsystems/infernode
exec "$ROOT/emu/MacOSX/o.emu" -c1 -pheap=512m -pmain=512m -pimage=512m "-r$ROOT/emu/MacOSX/../.." sh -l -c '
luciuisrv
echo activity create Main > /n/ui/ctl
speech9p &
sleep 1
/dis/veltro/tools9p -m /tool -p /dis/wm read list find search grep write edit exec launch spawn xenith ask diff json http git memory todo websearch mail present say hear
lucibridge -s &
lucifer
'
