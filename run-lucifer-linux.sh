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
    echo "ERROR: o.emu not found. Build with ./build-linux-amd64.sh first."
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

# llmsrv is the native Limbo Styx server for LLM access — it self-mounts at
# /n/llm and uses factotum for API key retrieval. No external Go process needed.
LUCIFER_CMD='luciuisrv; echo activity create Main > /n/ui/ctl; llmsrv &; sleep 1; /dis/veltro/tools9p -m /tool -p /dis/wm read list find search grep write edit exec launch spawn xenith ask diff json http git memory todo websearch mail present gap editor shell charon; lucibridge -v &; lucifer'

# --- Launch emulator ---
cd "$ROOT/emu/Linux"
echo brimstone > "$ROOT/lib/lucifer/theme/current"

exec "$EMU" -c0 $GEOMETRY -pheap=512m -pmain=512m -pimage=512m -r../.. sh -l -c "$LUCIFER_CMD"
