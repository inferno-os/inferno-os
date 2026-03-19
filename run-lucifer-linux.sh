#!/bin/sh
#
# Launch Lucifer UI on Linux
# Run from anywhere: sh /path/to/run-lucifer-linux.sh
#
# LLM integration uses the native llmsrv (Limbo Styx server) which runs
# inside the emulator — no external Go process needed. Set ANTHROPIC_API_KEY
# in the host environment; the Inferno profile provisions it into factotum.
#
# Usage:
#   ./run-lucifer-linux.sh
#   ./run-lucifer-linux.sh -g 1920x1080   # custom geometry
#

ROOT="$(cd "$(dirname "$0")" && pwd)"

EMU="$ROOT/emu/Linux/o.emu"

if [ ! -x "$EMU" ]; then
    echo "ERROR: o.emu not found. Build with ./build-linux-amd64.sh first." >&2
    exit 1
fi

# Parse arguments - pass through to emu
GEOMETRY=""
for arg in "$@"; do
    case "$arg" in
        -g) shift; GEOMETRY="-g $1"; shift ;;
        -g*) GEOMETRY="$arg"; shift ;;
        *) ;;
    esac
done

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "NOTE: ANTHROPIC_API_KEY not set - AI features will be unavailable."
    echo "  export ANTHROPIC_API_KEY=sk-ant-..."
fi

# LLM service (llmsrv or remote mount) is configured in lib/sh/profile.
# Do NOT start llmsrv here — the profile handles it via "sh -l".
LUCIFER_CMD='luciuisrv; echo activity create Main > /n/ui/ctl; sleep 1; /dis/veltro/tools9p -v -m /tool -b read,list,find,search,grep,write,edit,exec,launch,spawn,diff,json,http,git,memory,todo,plan,websearch,mail,keyring,present,gap -p /dis/wm read list find present say hear task memory gap keyring xenith editor shell charon launch; lucibridge -a 0 -v -s &; sleep 1; echo '"'"'create id=tasks type=taskboard label=Tasks'"'"' > /n/ui/activity/0/presentation/ctl; lucifer'

# --- Launch emulator ---
cd "$ROOT/emu/Linux"
echo brimstone > "$ROOT/lib/lucifer/theme/current"

exec "$EMU" -c0 $GEOMETRY -pheap=512m -pmain=512m -pimage=512m -r../.. sh -l -c "$LUCIFER_CMD"
