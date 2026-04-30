#!/bin/bash
# serve-llm.sh — Headless InferNode LLM 9P gateway (for systemd).
#
# Replaces the standalone llm9p Go daemon with the canonical Limbo
# llmsrv inside emu, loading lib/sh/serve-profile (a stripped-down
# rc script that excludes desktop/auth/Veltro overlays).
#
# Backend config is read inside emu from
#   ~/.infernode/lib/ndb/llm
# (same file the desktop uses).
#
# Logs go to stderr; under systemd they land in the journal.
#
# Listener: tcp!*!5640, no auth (-A). For production, swap to
# `listen -sk /usr/$user/keyring/default ...` and provision keys.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
EMU="$ROOT/emu/Linux/o.emu"
PROFILE_REL="lib/sh/serve-profile"
PROFILE_HOST="$ROOT/$PROFILE_REL"
PROFILE_INF="/$PROFILE_REL"

# Locate Ollama on PATH (it runs outside emu, on the host).
# Set OLLAMA_BIN=/full/path/to/ollama if it lives somewhere unusual
# (e.g. an external SSD on a Jetson).
if [ -n "${OLLAMA_BIN:-}" ] && [ -x "$OLLAMA_BIN" ]; then
	export PATH="$(dirname "$OLLAMA_BIN"):$PATH"
elif ! command -v ollama >/dev/null 2>&1; then
	for p in /usr/local/bin /usr/bin; do
		if [ -x "$p/ollama" ]; then
			export PATH="$p:$PATH"
			break
		fi
	done
fi

# Sanity checks
[ -x "$EMU" ]          || { echo "serve-llm: emu missing at $EMU" >&2; exit 1; }
[ -f "$PROFILE_HOST" ] || { echo "serve-llm: profile missing at $PROFILE_HOST" >&2; exit 1; }

# Pre-flight: warn (don't fail) if Ollama isn't reachable yet — systemd
# will Restart=always us, so a transient race is fine.
if ! curl -sf -m 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
	echo "serve-llm: WARN ollama at 127.0.0.1:11434 not responding" >&2
fi

echo "serve-llm: $(date -Iseconds) emu=$EMU root=$ROOT profile=$PROFILE_INF" >&2
exec "$EMU" -c1 "-r$ROOT" sh "$PROFILE_INF"
