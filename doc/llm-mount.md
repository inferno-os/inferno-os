# LLM Filesystem Mount for Inferno

This document describes how to use the LLM 9P filesystem with Inferno.

## Overview

The `llmsrv` service presents LLM providers (Anthropic API or Ollama/OpenAI-compatible)
as a 9P filesystem at `/n/llm`. Sessions are cloned from `/n/llm/new`, then prompts
are written to `/n/llm/{id}/ask` and responses read back from the same file.

## Local Service

llmsrv runs inside the Inferno emulator and self-mounts at `/n/llm`. The shell
profile (`lib/sh/profile`) starts it automatically:

```sh
llmsrv >[2] /dev/null &
```

Backend and model can be configured via flags:

```sh
# Anthropic API (default)
llmsrv &

# Ollama / OpenAI-compatible
llmsrv -b openai -u http://localhost:11434/v1 -M qwen3-coder:30b &
```

The Settings app (`LLM Service` category) provides a GUI for this configuration.

## Remote Service

Mount a remote llmsrv (or any compatible 9P LLM server) via dial+mount:

```sh
mount -A 'tcp!hephaestus!5640' /n/llm >[2] /dev/null
```

The Settings app can configure this as well — select "Remote (9P)" and enter
the dial address. Apply does the mount immediately; "Save to Profile" persists
it for next startup.

## Filesystem Structure

```
/n/llm/
├── new          # Read to clone a new session (returns session ID)
└── {id}/
    ├── ask      # Write prompt, read response
    ├── ctl      # Session control (model, system prompt)
    ├── tools    # Write tool definitions (JSON)
    ├── model    # Read/write model name
    └── stream   # Read streaming response chunks
```

## Usage from Inferno Shell

### Simple Query
```sh
id=`{cat /n/llm/new}
echo 'What is the capital of France' > /n/llm/$id/ask
cat /n/llm/$id/ask
```

## Troubleshooting

### /n/llm doesn't exist

1. Ensure you started emu through the shell: `sh -l -c 'xenith'`
2. Check the profile has `llmsrv &` or `mount -A` in the LLM section
3. For remote: verify the remote host is reachable

### Connection refused (remote)

The remote LLM service is not running or not listening on the expected port.

## Architecture Notes

Xenith forks its namespace at startup (`sys->pctl(Sys->FORKNS, ...)`), which
means mounts done from within Xenith are isolated. The profile mount happens
before Xenith starts, ensuring the LLM mount is inherited by Xenith's namespace.
