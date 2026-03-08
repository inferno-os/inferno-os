#!/bin/sh
# Start llm9p on :5640 if not already running.
# Called from lib/sh/profile via 'os sh' during Inferno startup.
# Works for both app bundle launches (llm9p already up, this is a no-op)
# and direct emu invocations from the terminal.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFERNODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Prefer the bundled binary; fall back to PATH.
LLM9P="$INFERNODE_ROOT/MacOSX/InferNode.app/Contents/MacOS/llm9p"
if [ ! -x "$LLM9P" ]; then
    LLM9P="$(command -v llm9p 2>/dev/null)"
fi
if [ -z "$LLM9P" ]; then
    exit 0
fi

# Ensure claude CLI is findable.
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# No-op if already listening.
if pgrep -qf "llm9p.*-addr :5640" 2>/dev/null; then
    exit 0
fi

nohup "$LLM9P" -backend cli -addr :5640 \
    </dev/null >>"$HOME/Library/Logs/InferNode-llm9p.log" 2>&1 &

# Wait up to 5 seconds for llm9p to be ready.
i=0
while [ $i -lt 10 ]; do
    nc -z 127.0.0.1 5640 2>/dev/null && exit 0
    sleep 0.5
    i=$((i + 1))
done
