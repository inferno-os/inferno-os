#!/bin/sh
# Launch Lucifer UI with Veltro agent bridge
# Run from anywhere: sh /path/to/run-lucifer.sh
ROOT="$(cd "$(dirname "$0")" && pwd)"

# Auto-detect platform
case "$(uname -s)" in
    Darwin) EMUDIR="$ROOT/emu/MacOSX" ;;
    Linux)  EMUDIR="$ROOT/emu/Linux" ;;
    *)      echo "Unsupported platform: $(uname -s)"; exit 1 ;;
esac

if [ ! -x "$EMUDIR/o.emu" ]; then
    echo "ERROR: $EMUDIR/o.emu not found. Build first."
    exit 1
fi

exec "$EMUDIR/o.emu" -c1 -pheap=512m -pmain=512m -pimage=512m "-r$EMUDIR/../.." sh -l -c '
luciuisrv
echo activity create Main > /n/ui/ctl
# LLM service (llmsrv or remote mount) is configured in lib/sh/profile.
# Do NOT start llmsrv here — the profile handles it.
speech9p &
sleep 1
/dis/veltro/tools9p -v -m /tool -b read,list,find,search,grep,write,edit,exec,launch,spawn,diff,json,http,git,memory,todo,plan,websearch,mail,keyring,present,gap -p /dis/wm read list find present say hear task memory gap keyring editor shell launch
lucibridge -a 0 -v -s &
sleep 1
echo '"'"'create id=tasks type=taskboard label=Tasks'"'"' > /n/ui/activity/0/presentation/ctl
lucifer
'
