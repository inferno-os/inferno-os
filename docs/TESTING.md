# Testing Guide

## Overview

The test suite covers: Limbo unit tests (run inside Inferno), host-side integration tests
(bash), and Inferno shell tests. Most Limbo tests skip gracefully when required services
(llmsrv, tools9p) are not running.

---

## Quick Start

From the project root:

```sh
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH

# Build all tests
cd tests && mk install && cd ..

# Run all Limbo tests via the runner
./emu/MacOSX/o.emu -r. /tests/runner.dis

# Run a specific test
./emu/MacOSX/o.emu -r. /tests/veltro_tools_test.dis -v

# Run host integration tests
./tests/host/pathmanage_test.sh
./tests/host/tools9p_integration_test.sh
```

---

## Limbo Tests (in `dis/tests/`)

Run inside the Inferno emulator. All compiled to `dis/tests/*.dis`.

### Core

| Test | What it covers | Requires |
|------|----------------|----------|
| `hello_test` | Basic smoke test | nothing |
| `asyncio_test` | Channels, spawned tasks, async I/O | nothing |
| `spawn_test` | Process spawning | nothing |
| `spawn_exec_test` | Process exec after spawn | nothing |
| `stderr_test` | Standard error output | nothing |
| `tempfile_test` | Temporary file operations | nothing |

### AI Agent

| Test | What it covers | Requires |
|------|----------------|----------|
| `agentlib_test` | `buildtooldefs`, `parsellmresponse`, `buildtoolresults`, session creation | `/n/llm` (skips without) |
| `tooluse_test` | End-to-end native tool_use protocol with llmsrv | `/n/llm` (skips without) |
| `veltro_test` | Tool module loading: name(), doc(), basic exec() | nothing |
| `veltro_tools_test` | diff, json, memory, todo tool execution | nothing |
| `veltro_security_test` | Namespace restriction: restrictdir, restrictns, verifyns | nothing |
| `veltro_concurrent_test` | Concurrent tool invocations | nothing |
| `pathmanage_test` | tools9p path management: bindpath, unbindpath, /tool/paths | `/tool` (skips without) |
| `tools9p_test` | tools9p 9P protocol: tool listing, tool exec via 9P, ctl add/remove | `/tool` (skips without) |

### GUI

| Test | What it covers | Requires |
|------|----------------|----------|
| `luciuisrv_test` | All luciuisrv ctl commands: conversation, presentation, context, events | nothing (loads server in-process) |
| `lucifer_flicker_test` | Lucifer rendering regression | nothing |
| `pres_launch_test` | Presentation zone launch and render | nothing |

### Networking / Crypto

| Test | What it covers | Requires |
|------|----------------|----------|
| `crypto_test` | Cryptographic primitives (18 test vectors) | nothing |
| `secp256k1_test` | secp256k1 ECDSA keygen, sign, recover (18 tests) | nothing |
| `ethcrypto_test` | RLP encoding, EIP-155 signing, EIP-712, address derivation (15 tests) | nothing |
| `x402_test` | x402 v2 payment protocol parsing and authorization (9 tests) | nothing |
| `tls_crypto_test` | TLS crypto operations | nothing |
| `tls_protocol_test` | TLS protocol handshake | nothing |
| `ssl_transport_test` | SSL transport layer | nothing |
| `tls_live_test` | Live TLS connection | network |
| `tcp_test` | TCP networking | network |
| `webclient_test` | HTTP client | network |
| `9p_export_test` | 9P protocol export | nothing |
| `x509_test` | X.509 certificate parsing | nothing |
| `imap_test` | IMAP client | network + IMAP server |
| `git_test` | Git operations | git repo |

### Other

| Test | What it covers | Requires |
|------|----------------|----------|
| `jit_test` | JIT compiler correctness | nothing |
| `pdf_test` | PDF parsing and rendering | nothing |
| `pdf_conformance_test` | 98.3% PDF conformance across 8 corpora | test PDFs |
| `outlinefont_test` | CFF/TrueType font rendering | nothing |
| `edit_test` | Edit tool operations | nothing |
| `cowfs_test` | Copy-on-write filesystem | nothing |
| `goroutine_leak_test` | Goroutine/channel leak detection | nothing |
| `sdl3_test` | SDL3 GPU backend | SDL3 display |

---

## Running with llmsrv

Tests that require the LLM (`agentlib_test`, `tooluse_test`) need llmsrv running.
The profile starts it automatically with `sh -l`. For manual testing:

```sh
# Run emu with profile (starts llmsrv automatically)
./emu/MacOSX/o.emu -r. sh -l

# Verify mount inside emu
./emu/MacOSX/o.emu -r. /dis/sh.dis
# Inside Inferno:
mount -A tcp!127.0.0.1!5640 /n/llm
cat /n/llm/new  # Should print a session ID
```

---

## Running with tools9p

Tests that require tools9p (`pathmanage_test`, `tools9p_test`) need it running at `/tool`.
These tests skip gracefully if it's not mounted.

To run them meaningfully, use the host integration test wrappers which start tools9p
themselves:

```sh
./tests/host/pathmanage_test.sh
./tests/host/tools9p_integration_test.sh
```

Or start tools9p manually inside Inferno before running the Limbo test:

```sh
# Inside Inferno shell:
tools9p read list find write exec &
sleep 2
/tests/pathmanage_test.dis -v
/tests/tools9p_test.dis -v
```

---

## Host Integration Tests (in `tests/host/`)

Bash tests that run on the host OS. Each starts emu with required services.

### Agent / Tools

| Test | What it covers |
|------|----------------|
| `pathmanage_test.sh` | tools9p path management: bindpath/unbindpath/idempotency |
| `tools9p_integration_test.sh` | tools9p tool exec via 9P, ctl add/remove, help |

### Wallet / Crypto / Auth

| Test | What it covers |
|------|----------------|
| `wallet9p_test.sh` | wallet9p basic operations: create account, read address, sign hash |
| `wallet_e2e_test.sh` | Base Sepolia RPC connectivity and balance queries |
| `wallet_persist_test.sh` | Wallet key survival across emu restarts via factotum/secstore (7 tests) |
| `secstore_logon_test.sh` | Secstore + factotum persistence: PAK auth, key round-trip (10 tests) |
| `payfetch_test.sh` | x402 payfetch end-to-end payment flow (requires x402-test-server) |

### Test Safety

All wallet/auth integration tests use dedicated test user accounts (`testuser-walletpersist`,
`testuser-seclogon`, `testuser-payfetch`). They never touch the real user's secstore data.

Run individually:
```sh
./tests/host/pathmanage_test.sh [-v]
./tests/host/tools9p_integration_test.sh [-v]
./tests/host/wallet9p_test.sh
./tests/host/secstore_logon_test.sh
```

---

## Inferno Shell Tests (in `tests/inferno/`)

Shell scripts run inside Inferno. Invoked by `tests/runner.b` or manually.

| Test | What it covers | Requires |
|------|----------------|----------|
| `lucifer.sh` | luciuisrv ctl commands end-to-end | nothing |
| `lucibridge.sh` | lucibridge startup and session init | `/n/llm` |
| `lucibridge_tools.sh` | lucibridge tool_use round-trip | `/n/llm` |
| `lucifer_presentation_test.rc` | Inject artifacts into running Lucifer session | running Lucifer |
| `veltro_tool_test.rc` | Tool execution via Veltro (19 tool tests) | tools9p |

---

## Test Runner

`tests/runner.b` (compiled to `dis/tests/runner.dis`) runs all `*_test.dis` files in
`dis/tests/` plus all `*.sh` scripts in `tests/inferno/`. It reports total counts.

```sh
# Run all tests
./emu/MacOSX/o.emu -r. /tests/runner.dis

# Verbose mode
./emu/MacOSX/o.emu -r. /tests/runner.dis -v

# See runner source
cat tests/runner.b
```

---

## What Is NOT Automated

The following require manual verification or a running full Lucifer session:

1. **End-to-end LLM agent turns** — full veltro session: prompt → tool calls → response.
   The `tooluse_test` covers the protocol, but a complete multi-turn agent session with
   real tool use requires llmsrv and a user prompt.

2. **GUI rendering** — lucifer's draw stack (zone layout, font rendering, PDF display)
   cannot be tested headlessly. `luciuisrv_test` covers the 9P state machine; the
   rendering layer is verified manually.

3. **Context zone → lucibridge sync** — the full chain "user clicks [-] on tool → lucictx
   writes to /tool/ctl → lucibridge picks up change on next turn → LLM loses schema"
   requires a running Lucifer + lucibridge + llmsrv. The individual pieces are tested
   (luciuisrv_test, pathmanage_test, tooluse_test) but the end-to-end chain is not.

4. **Cross-host 9P** — requires the Jetson to be reachable over ZeroTier.

---

## Adding New Tests

1. Write `tests/<name>_test.b` following the pattern in `tests/example_test.b`
2. Add `<name>_test.dis` to the `TARG=` list in `tests/mkfile`
3. If special include paths are needed, add a rule like:
   ```
   <name>_test.dis: <name>_test.b
       limbo -I$ROOT/module -I$ROOT/appl/veltro -gw <name>_test.b
   ```
4. Build: `cd tests && mk install`
5. Run: `./emu/MacOSX/o.emu -r. /tests/<name>_test.dis -v`

Tests go to `dis/tests/<name>_test.dis` (set by `DISBIN=$ROOT/dis/tests` in mkfile).

---

## Known Skips

These tests always skip in standard CI (no required services available):

- `agentlib_test`: 6 skipped (require `/n/llm`)
- `veltro_test`: 2 skipped (require network/console)
- `pathmanage_test`: 5 skipped (require `/tool` to be mounted)
- `tools9p_test`: all skip (require `/tool` to be mounted)
- `tooluse_test`: all skip (require `/n/llm`)
