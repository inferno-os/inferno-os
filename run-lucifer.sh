#!/bin/sh
# Launch Lucifer UI with Veltro agent bridge
# Run from anywhere: sh /path/to/run-lucifer.sh
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/emu/MacOSX/o.emu" -c1 -pheap=512m -pmain=512m -pimage=512m "-r$ROOT/emu/MacOSX/../.." sh -l -c '
luciuisrv
echo activity create Main > /n/ui/ctl
speech9p &
sleep 1
/dis/veltro/tools9p -m /tool -b "read,list,find,search,grep,write,edit,exec,launch,spawn,diff,json,http,git,websearch,mail" -p /dis/wm read list find present ask say hear task todo memory gap
lucibridge -a 0 -s &
sleep 1
echo "create id=tasks type=taskboard label=Tasks" > /n/ui/activity/0/presentation/ctl
lucifer
'
