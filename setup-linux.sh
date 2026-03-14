#!/bin/bash
#
# InferNode Setup — Linux (Ubuntu/Debian)
#
# Configures the LLM backend that Veltro needs to operate.
# Choose between an Anthropic API key or a local Ollama instance.
#

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

# ── Colours (if terminal supports them) ────────────────────────────
if [ -t 1 ]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    RED="\033[31m"
    CYAN="\033[36m"
    RESET="\033[0m"
else
    BOLD="" DIM="" GREEN="" YELLOW="" RED="" CYAN="" RESET=""
fi

info()  { printf "${CYAN}▸${RESET} %s\n" "$*"; }
ok()    { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${RESET} %s\n" "$*"; }
fail()  { printf "${RED}✗${RESET} %s\n" "$*"; exit 1; }

# ── Banner ─────────────────────────────────────────────────────────
printf "\n"
printf "${BOLD}InferNode Setup${RESET}\n"
printf "${DIM}Configure the LLM backend for Veltro${RESET}\n"
printf "\n"

# ── Choose backend ─────────────────────────────────────────────────
printf "Veltro needs an LLM to work. Choose your backend:\n"
printf "\n"
printf "  ${BOLD}1)${RESET} Anthropic API key ${DIM}(recommended — best quality)${RESET}\n"
printf "  ${BOLD}2)${RESET} Local model via Ollama ${DIM}(free, private, ~2–5 GB download)${RESET}\n"
printf "\n"

while true; do
    printf "Enter ${BOLD}1${RESET} or ${BOLD}2${RESET}: "
    read -r choice
    case "$choice" in
        1) BACKEND=api;    break ;;
        2) BACKEND=ollama; break ;;
        *) warn "Please enter 1 or 2." ;;
    esac
done

printf "\n"

# ── Helper: write key file inside Inferno FS ───────────────────────
write_key() {
    mkdir -p "$ROOT/lib/veltro/keys"
    printf "%s" "$2" > "$ROOT/lib/veltro/keys/$1"
    chmod 600 "$ROOT/lib/veltro/keys/$1"
}

# ── Path 1: Anthropic API ──────────────────────────────────────────
setup_anthropic() {
    info "Anthropic API setup"
    printf "\n"

    # Check for existing key
    existing=""
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        existing="$ANTHROPIC_API_KEY"
    elif [ -f "$ROOT/lib/veltro/keys/anthropic" ]; then
        existing="$(cat "$ROOT/lib/veltro/keys/anthropic" 2>/dev/null)"
    fi

    if [ -n "$existing" ]; then
        masked="${existing:0:8}...${existing: -4}"
        ok "Found existing API key: $masked"
        printf "  Use this key? [Y/n] "
        read -r yn
        case "$yn" in
            [Nn]*) existing="" ;;
        esac
    fi

    if [ -z "$existing" ]; then
        printf "  Paste your Anthropic API key (starts with sk-ant-): "
        read -r apikey
        if [ -z "$apikey" ]; then
            fail "No API key provided."
        fi
    else
        apikey="$existing"
    fi

    # Validate key format
    case "$apikey" in
        sk-ant-*) ;;
        *) warn "Key doesn't start with sk-ant-. Proceeding anyway." ;;
    esac

    # Quick validation
    info "Validating API key..."
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "x-api-key: $apikey" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        "https://api.anthropic.com/v1/messages" 2>/dev/null) || status="000"

    case "$status" in
        200) ok "API key is valid." ;;
        401) fail "API key rejected (401 Unauthorized). Check your key and try again." ;;
        000) warn "Could not reach api.anthropic.com — key saved but not validated." ;;
        *)   warn "Unexpected status $status — key saved but check your account." ;;
    esac

    # Store the key
    write_key "anthropic" "$apikey"
    ok "Key saved to lib/veltro/keys/anthropic"

    export ANTHROPIC_API_KEY="$apikey"

    # Offer to add to shell profile
    printf "\n"
    printf "  Add ANTHROPIC_API_KEY to your shell profile? [y/N] "
    read -r yn
    case "$yn" in
        [Yy]*)
            shell_rc=""
            if [ -f "$HOME/.bashrc" ]; then
                shell_rc="$HOME/.bashrc"
            elif [ -f "$HOME/.zshrc" ]; then
                shell_rc="$HOME/.zshrc"
            elif [ -f "$HOME/.profile" ]; then
                shell_rc="$HOME/.profile"
            fi
            if [ -n "$shell_rc" ]; then
                if ! grep -q "ANTHROPIC_API_KEY" "$shell_rc" 2>/dev/null; then
                    printf '\nexport ANTHROPIC_API_KEY="%s"\n' "$apikey" >> "$shell_rc"
                    ok "Added to $shell_rc"
                else
                    warn "ANTHROPIC_API_KEY already in $shell_rc — not modified."
                fi
            else
                warn "Could not find shell profile. Set it manually:"
                printf '  export ANTHROPIC_API_KEY="%s"\n' "$apikey"
            fi
            ;;
    esac

    printf "\n"
    ok "Anthropic backend configured."
    printf "  Model: ${BOLD}claude-sonnet-4-5${RESET} (default, configurable at runtime)\n"
}

# ── Path 2: Ollama ─────────────────────────────────────────────────
setup_ollama() {
    info "Ollama setup (local LLM)"
    printf "\n"

    # Check if Ollama is installed
    if command -v ollama &>/dev/null; then
        ok "Ollama is installed: $(command -v ollama)"
        ollama_version=$(ollama --version 2>/dev/null || echo "unknown")
        printf "  Version: %s\n" "$ollama_version"
    else
        info "Ollama not found. Installing..."
        printf "\n"

        printf "  Install via official installer? (requires curl + sudo) [Y/n] "
        read -r yn
        case "$yn" in
            [Nn]*)
                info "Install manually from https://ollama.com/download and re-run this script."
                exit 0
                ;;
        esac

        curl -fsSL https://ollama.com/install.sh | sh

        if ! command -v ollama &>/dev/null; then
            fail "Ollama installation failed. Install from https://ollama.com/download and re-run."
        fi
        ok "Ollama installed."
    fi

    # Ensure Ollama is running
    printf "\n"
    info "Checking if Ollama is running..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:11434/api/tags" 2>/dev/null | grep -q "200"; then
        ok "Ollama is running."
    else
        info "Starting Ollama..."

        # Try systemd first (common on Ubuntu)
        if command -v systemctl &>/dev/null && systemctl list-unit-files ollama.service &>/dev/null 2>&1; then
            sudo systemctl start ollama 2>/dev/null || true
            sleep 2
        fi

        # Fall back to direct launch
        if ! curl -s -o /dev/null "http://localhost:11434/api/tags" 2>/dev/null; then
            ollama serve &>/dev/null &
            OLLAMA_PID=$!
            sleep 2
        fi

        if curl -s -o /dev/null "http://localhost:11434/api/tags" 2>/dev/null; then
            ok "Ollama is running."
        else
            warn "Could not start Ollama. You may need to run 'ollama serve' manually."
        fi
    fi

    # Choose a model
    printf "\n"
    printf "Choose a model to download:\n"
    printf "\n"
    printf "  ${BOLD}1)${RESET} llama3.2:3b   ${DIM}(~2 GB — fast, good for most tasks)${RESET}\n"
    printf "  ${BOLD}2)${RESET} llama3.1:8b   ${DIM}(~5 GB — better quality, needs 8+ GB RAM)${RESET}\n"
    printf "  ${BOLD}3)${RESET} qwen2.5:7b    ${DIM}(~4 GB — strong reasoning, good tool use)${RESET}\n"
    printf "  ${BOLD}4)${RESET} Custom         ${DIM}(enter any Ollama model name)${RESET}\n"
    printf "\n"

    while true; do
        printf "Enter choice [1]: "
        read -r mchoice
        mchoice="${mchoice:-1}"
        case "$mchoice" in
            1) MODEL="llama3.2:3b";  break ;;
            2) MODEL="llama3.1:8b";  break ;;
            3) MODEL="qwen2.5:7b";   break ;;
            4)
                printf "  Model name: "
                read -r MODEL
                [ -z "$MODEL" ] && { warn "No model name given."; continue; }
                break
                ;;
            *) warn "Enter 1–4." ;;
        esac
    done

    # Pull the model
    printf "\n"
    info "Pulling $MODEL (this may take a few minutes)..."
    ollama pull "$MODEL"
    ok "$MODEL is ready."

    # Write Ollama config for Veltro
    mkdir -p "$ROOT/lib/veltro"
    cat > "$ROOT/lib/veltro/llm.cfg" <<EOF
# Veltro LLM configuration — generated by setup-linux.sh
backend=openai
url=http://localhost:11434/v1
model=$MODEL
EOF
    ok "Config saved to lib/veltro/llm.cfg"

    printf "\n"
    ok "Ollama backend configured."
    printf "  Model: ${BOLD}$MODEL${RESET}\n"
    printf "  Endpoint: ${BOLD}http://localhost:11434/v1${RESET}\n"
    printf "\n"
    printf "${DIM}  Tip: Ollama must be running before you start InferNode.${RESET}\n"
    printf "${DIM}  Start it with: ollama serve  (or: sudo systemctl start ollama)${RESET}\n"
}

# ── Optional: Brave Search API key ─────────────────────────────────
setup_brave_search() {
    printf "\n"
    printf "${DIM}─────────────────────────────────────────────────${RESET}\n"
    printf "\n"
    printf "Veltro can search the web using the Brave Search API (optional).\n"
    printf "  Get a free key at: https://brave.com/search/api/\n"
    printf "\n"
    printf "  Paste your Brave Search API key (or press Enter to skip): "
    read -r bravekey
    if [ -n "$bravekey" ]; then
        write_key "brave" "$bravekey"
        ok "Brave Search key saved."
    else
        info "Skipped. You can add it later to lib/veltro/keys/brave"
    fi
}

# ── Dispatch ───────────────────────────────────────────────────────
case "$BACKEND" in
    api)    setup_anthropic ;;
    ollama) setup_ollama    ;;
esac

setup_brave_search

# ── Done ───────────────────────────────────────────────────────────
printf "\n"
printf "${DIM}─────────────────────────────────────────────────${RESET}\n"
printf "\n"
printf "${GREEN}${BOLD}Setup complete!${RESET}\n"
printf "\n"

# Detect emulator
EMU=""
if [ -x "$ROOT/emu/Linux/o.emu" ]; then
    EMU="./emu/Linux/o.emu -r."
fi

if [ -n "$EMU" ]; then
    printf "Launch InferNode:\n"
    printf "  cd %s\n" "$ROOT"
    printf "  %s\n" "$EMU"
else
    printf "Build InferNode first:\n"
    printf "  ./build-linux-amd64.sh  ${DIM}(x86_64)${RESET}\n"
    printf "  ./build-linux-arm64.sh  ${DIM}(ARM64)${RESET}\n"
fi
printf "\n"
