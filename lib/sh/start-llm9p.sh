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

# Prefer API backend (full tool_use support) when ANTHROPIC_API_KEY is available.
# Fall back to CLI backend (Claude Max subscription, no custom tool schemas).
if [ -z "$ANTHROPIC_API_KEY" ]; then
    ANTHROPIC_API_KEY=$(plutil -extract EnvironmentVariables.ANTHROPIC_API_KEY raw \
        "$HOME/Library/LaunchAgents/com.nervsystems.llm9p.plist" 2>/dev/null)
fi
if [ -n "$ANTHROPIC_API_KEY" ]; then
    export ANTHROPIC_API_KEY
    BACKEND="api"
else
    BACKEND="cli"
fi

nohup "$LLM9P" -backend "$BACKEND" -addr :5640 \
    </dev/null >>"$HOME/Library/Logs/InferNode-llm9p.log" 2>&1 &

# Wait up to 15 seconds for llm9p to be ready.
i=0
while [ $i -lt 30 ]; do
    nc -z 127.0.0.1 5640 2>/dev/null && exit 0
    sleep 0.5
    i=$((i + 1))
done
