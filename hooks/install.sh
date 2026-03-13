#!/bin/sh
# Install git hooks from hooks/ into .git/hooks/
# Run once after clone: ./hooks/install.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKDIR="$ROOT/.git/hooks"

for hook in "$ROOT"/hooks/post-merge; do
    name="$(basename "$hook")"
    if [ "$name" = "install.sh" ]; then
        continue
    fi
    cp "$hook" "$HOOKDIR/$name"
    chmod +x "$HOOKDIR/$name"
    echo "installed $name"
done
