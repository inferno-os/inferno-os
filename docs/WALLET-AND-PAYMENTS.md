# Wallet, Payments, and Key Management

This document covers InferNode's cryptocurrency wallet system, the x402 payment protocol integration, the secstore-based key persistence architecture, and the login screen.

## Overview

InferNode provides a native cryptocurrency wallet that enables Veltro AI agents to make autonomous payments for external services. The system follows Plan 9 architecture principles: everything is a file, secrets are managed by factotum, and persistent storage uses secstore.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User / Agent                          │
├──────────┬──────────┬───────────┬───────────────────────┤
│ Wallet   │ Veltro   │ payfetch  │  Keyring GUI          │
│ GUI App  │ wallet   │ tool      │  (credential mgmt)    │
│          │ tool     │ (x402)    │                        │
├──────────┴──────────┴───────────┴───────────────────────┤
│                   wallet9p (9P server)                   │
│              /n/wallet/{acct}/address,balance,sign...    │
├─────────────────────────────────────────────────────────┤
│  ethcrypto     │  ethrpc        │  x402         │ stripe │
│  (RLP, EIP-155)│  (JSON-RPC)    │  (HTTP 402)   │ (fiat) │
├─────────────────────────────────────────────────────────┤
│              factotum (in-memory key agent)               │
│                   /mnt/factotum/ctl                       │
├─────────────────────────────────────────────────────────┤
│              secstore (encrypted persistent storage)      │
│                 PAK authentication, AES-256-GCM           │
├─────────────────────────────────────────────────────────┤
│  secp256k1 + Keccak-256 (libsec C primitives)            │
│  keyring.m builtins                                       │
└─────────────────────────────────────────────────────────┘
```

## Boot Sequence

```
1. secstored starts (listens on tcp!*!5356)
2. factotum starts (empty, no keys)
3. wm/logon displays login screen
4. User enters secstore password
5. Login screen:
   a. Connects to secstore, authenticates (PAK)
   b. Loads encrypted keys into factotum
   c. Establishes save-back path for new keys
6. llmsrv, tools9p, lucibridge, lucifer start
7. System fully operational with all keys available
```

For headless operation, factotum can be started with `-S tcp!localhost!5356 -P password` directly.

## Login Screen (wm/logon)

The login screen is a fullscreen raw Draw application that runs before the window manager. It handles secstore authentication and key loading.

### First Boot

On first boot, no secstore account exists. The login screen detects this and prompts "First boot — choose a secstore password." Entering a password creates the secstore account (PAK verifier) and proceeds to boot. All keys added during the session are automatically saved to secstore.

### Subsequent Boots

The login screen prompts for the secstore password. On successful authentication, all stored keys (wallet keys, API keys, email credentials) are loaded into factotum. The system then boots with all credentials available.

### Skipping

Pressing Escape skips secstore unlock. The system boots with an empty factotum — wallet accounts won't be available and API keys must be provisioned from environment variables.

### Headless Fallback

When no display is available (headless server, Jetson), the login screen exits gracefully. Use `auth/factotum -S tcp!localhost!5356 -P password` in the shell to connect to secstore manually.

## Secstore (Persistent Key Storage)

Secstore is the Plan 9 secure storage service. It encrypts all keys at rest using AES-256-GCM and authenticates clients using the PAK (Password Authenticated Key exchange) protocol.

### How It Works

- **secstored** runs as a background service, listening on TCP port 5356
- Keys are stored in `/usr/inferno/secstore/<username>/`
- The `factotum` file contains all keys, encrypted with AES-256-GCM
- The `PAK` file contains the password verifier (never the password itself)
- Authentication uses 1024-bit modular exponentiation (takes ~5 seconds)

### Key Persistence Flow

```
Create wallet account
  → key stored in factotum memory
  → wallet9p writes "sync" to /mnt/factotum/ctl (async)
  → factotum connects to secstore (PAK auth)
  → factotum encrypts all keys with AES-256-GCM
  → encrypted blob stored in secstore
```

### Factotum Secstore CTL Command

A running factotum instance can be connected to secstore mid-session:

```
echo 'secstore tcp!localhost!5356 username password' > /mnt/factotum/ctl
```

This is used by the login screen to establish the save-back path after authentication.

### Cross-Machine Key Sync

secstored can serve keys to remote machines:

```
# On the key server (e.g., Mac)
auth/secstored    # already running from boot

# On the remote machine (e.g., Jetson)
auth/factotum -S tcp!mac-ip!5356 -u username -P password
```

All keys (wallet, API, email) sync automatically.

## Cryptographic Primitives

### secp256k1 (libsec/secp256k1.c)

Clean-room implementation of the secp256k1 elliptic curve used by Ethereum and Bitcoin. Follows the same patterns as the existing P-256 implementation in `libsec/ecc.c`.

- **Constant-time Montgomery ladder** in Jacobian coordinates
- **RFC 6979 deterministic k** for reproducible signatures (required by Ethereum)
- **Recovery ID** in signatures (byte 65) for `ecrecover`
- **Low-S normalization** (BIP-62 / EIP-2)
- **Host OS CSPRNG** (`arc4random_buf` on macOS, `getrandom` on Linux) for key generation

Keyring builtins:
```limbo
kr->secp256k1_keygen()           # → (priv[32], pub[65])
kr->secp256k1_pubkey(priv)       # → pub[65]
kr->secp256k1_sign(priv, hash)   # → sig[65] (r||s||v)
kr->secp256k1_recover(hash, sig) # → pub[65]
```

### Keccak-256 (libsec/keccak256.c)

Ethereum's hash function. Identical to SHA3-256 except for the domain separator byte: Keccak uses `0x01`, SHA-3 uses `0x06`.

```limbo
kr->keccak256(data, len, digest)  # → 32-byte hash
```

## Ethcrypto Library (module/ethcrypto.m)

Pure Limbo translation of go-ethereum's core crypto operations.

### Address Derivation

```limbo
pub := kr->secp256k1_pubkey(privkey);
addr := ethcrypto->pubkeytoaddr(pub);     # Keccak-256(pub[1:])[12:]
addrstr := ethcrypto->addrtostr(addr);    # EIP-55 checksummed hex
```

### RLP Encoding

Recursive Length Prefix encoding for Ethereum transactions:

```limbo
ethcrypto->rlpencode_bytes(data)           # encode byte string
ethcrypto->rlpencode_uint(value)           # encode unsigned integer
ethcrypto->rlpencode_list(items)           # encode list of encoded items
```

### Transaction Signing (EIP-155)

```limbo
tx := ref Ethcrypto->EthTx(
    nonce, gasprice, gaslimit, dst, value, data, chainid
);
rawtx := ethcrypto->signtx(tx, privkey);   # signed RLP-encoded transaction
```

### EIP-712 Typed Data Hashing

Used by the x402 payment protocol for authorization signing:

```limbo
hash := ethcrypto->eip712hash(domainsep, structhash);
```

### Limbo Big Integer Caution

Limbo truncates `big` hex literals larger than `0x7FFFFFFF`. Use arithmetic with variables:

```limbo
# WRONG: big 16r4A817C800 → truncated to negative
# RIGHT:
billion := big 1000000000;
gwei20 := big 20 * billion;
```

## Wallet9p (9P File Server)

The wallet filesystem mounts at `/n/wallet/` and provides account management, signing, and balance queries.

### File Tree

```
/n/wallet/
├── ctl              rw   "network <name>", "default <name>", "rpc <url>"
├── accounts         r    newline-separated account names
├── new              rw   write: "eth chain name" or "import eth chain name hexkey"
│                         read: account name after creation
└── {name}/
    ├── address      r    public address (EIP-55 checksummed)
    ├── balance      r    live balance from blockchain RPC
    ├── chain        rw   chain name
    ├── sign         rw   write: hex hash → read: hex signature
    ├── pay          rw   write: "amount recipient" → read: txhash
    ├── ctl          rw   "budget maxpertx maxpersess currency"
    └── history      r    recent transactions
```

### Account Creation

```sh
echo 'eth ethereum myaccount' > /n/wallet/new
cat /n/wallet/new    # → myaccount
cat /n/wallet/myaccount/address    # → 0x...
```

### Importing a Private Key

```sh
echo 'import eth ethereum myaccount 0123456789abcdef...' > /n/wallet/new
```

### Signing

```sh
echo 'abcdef0123456789...' > /n/wallet/myaccount/sign    # 32-byte hash as hex
cat /n/wallet/myaccount/sign    # → 65-byte signature as hex
```

### Network Selection

wallet9p supports multiple networks, each with its own RPC endpoint and USDC contract:

| Network | RPC Endpoint | USDC Contract | Chain ID |
|---------|-------------|---------------|----------|
| Ethereum Sepolia | ethereum-sepolia-rpc.publicnode.com | 0x1c7D4B196... | 11155111 |
| Base Sepolia | sepolia.base.org | 0x036CbD538... | 84532 |
| Ethereum Mainnet | eth.llamarpc.com | 0xA0b86991... | 1 |
| Base | mainnet.base.org | 0x833589fCD... | 8453 |

Switch network:
```sh
echo 'network Ethereum Sepolia' > /n/wallet/ctl
```

### Account Persistence

wallet9p restores accounts from factotum on startup. It scans for `service=wallet-*` keys and derives addresses from the stored private keys. Keys are stored in factotum as:

```
key proto=pass service=wallet-eth-{name} user=key !password={hex-encoded-privkey}
```

When a new account is created, wallet9p immediately triggers a factotum sync to persist the key to secstore (async, non-blocking).

### Budget Enforcement

```sh
echo 'budget 1000000 10000000 USDC' > /n/wallet/myaccount/ctl
```

Budget limits are enforced server-side in wallet9p — agents cannot bypass them.

## Ethereum JSON-RPC Client (module/ethrpc.m)

Speaks the standard Ethereum JSON-RPC API over HTTPS.

```limbo
ethrpc->init("https://ethereum-sepolia-rpc.publicnode.com");
(balance, err) := ethrpc->getbalance("0x...");           # wei as decimal string
(tokbal, err) := ethrpc->tokenbalance(usdc_addr, "0x...");  # ERC-20 balance
(nonce, err) := ethrpc->getnonce("0x...");
(txhash, err) := ethrpc->sendrawtx("0x...");
(receipt, err) := ethrpc->waitreceipt(txhash, 30);

# Conversions
ethrpc->weitoeth("1000000000000000000")    # → "1"
ethrpc->weitotoken("20000000", 6)          # → "20" (USDC)
```

## x402 Payment Protocol (module/x402.m)

Implements the x402 v2 specification for HTTP 402 payment flows.

### Protocol Flow

```
1. Client requests resource
2. Server returns 402 with payment requirements (JSON)
3. Client selects payment option
4. Client signs EIP-3009 authorization via wallet9p
5. Client retries with PAYMENT-SIGNATURE header
6. Server verifies and settles payment via facilitator
7. Server returns resource
```

### Library API

```limbo
# Parse 402 response
(pr, err) := x402->parse402(body);

# Select best payment option for our chain
opt := x402->selectoption(pr, "base");

# Sign and build payment header
(payload, err) := x402->authorize(opt, pr.resource, "myaccount");

# Parse settlement response
(sr, err) := x402->parsesettlement(body);
```

### Chain/Network Mapping

```limbo
x402->chaintonetwork("base")        # → "eip155:8453"
x402->networktochainid("eip155:1")  # → 1
```

## Veltro Tools

### wallet tool

Agent-facing interface to wallet9p:

```
wallet accounts                    List all wallet accounts
wallet address <account>           Show public address
wallet balance <account>           Show balance
wallet chain <account>             Show blockchain network
wallet sign <account> <hexhash>    Sign a 32-byte hash
wallet history <account>           Show recent transactions
```

### payfetch tool

HTTP client with automatic x402 payment handling:

```
payfetch <url>                     Fetch URL, pay if 402
payfetch <url> -a <account>        Use specific wallet account
payfetch <url> -a <account> -c <chain>    Specify chain preference
```

When a server returns 402 Payment Required:
1. Parses x402 payment requirements
2. Checks wallet budget
3. Signs payment authorization
4. Retries with PAYMENT-SIGNATURE header
5. Reports what was paid before returning content

The agent explicitly chooses `payfetch` over `webfetch` when willing to spend money.

### Namespace Security

Wallet access is gated by namespace capabilities:

- Agent needs `"/n/wallet"` in `caps.paths` to access the wallet
- `/mnt/factotum/ctl` is blocked by nsconstruct — agents never see private keys
- Budget enforcement is server-side in wallet9p
- The agent writes a hash to `sign`, reads back a signature — the key never enters the agent's address space

## Wallet GUI App (wm/wallet.b)

Graphical wallet manager for users. Uses the custom widget toolkit (no Tk).

### Layout

- **Left pane (35%)**: Account list
- **Right pane (65%)**: Network selector dropdown, account details (name, chain, address, balance)

### Features

- **Network dropdown**: Switch between Ethereum Sepolia, Base Sepolia, Ethereum Mainnet, Base
- **Account creation**: Right-click → New Ethereum Account
- **Key import**: Right-click → Import Private Key
- **Balance display**: USDC and ETH on separate lines, fetched asynchronously
- **Context menu** (right-click on detail pane): Copy Address, Copy Account Name, Refresh Balance
- **Auto-start**: Starts wallet9p automatically if not running
- **Persistence**: Accounts survive emu restart via factotum/secstore

### Balance Loading

Balances are fetched asynchronously in a background goroutine. The GUI shows "loading..." immediately and updates when the RPC call completes. A 30-second timer refreshes automatically.

## Stripe Fiat Backend (module/stripe.m)

Basic Stripe API client for fiat payments. API key stored in factotum.

```limbo
stripe->init(apikey);
(id, err) := stripe->createpayment(amount, "usd", "description");
(balance, err) := stripe->balance();
(charges, err) := stripe->recent(10);
```

## Dropdown Widget

A new widget added to the toolkit (`module/widget.m`):

```limbo
dd := Dropdown.mk(rect, items, selectedIndex);
dd.label = "Network:";    # optional prefix
dd.draw(screen);

# On click: opens popup overlay with all options
if(dd.contains(ptr.xy))
    dd.click(screen, ptrchan);    # blocks until selection

dd.value()    # → selected item string
```

The popup renders over the parent image, highlights items on hover, and restores the underlying pixels on close.

## Post-Quantum Readiness

The wallet architecture is designed for future post-quantum signature schemes:

- `Account.accttype` dispatches signing by type — adding `ACCT_PQ` is one new case
- ML-DSA-65/87 (FIPS 204) is already available in keyring.m
- TLS connections to RPC endpoints use hybrid X25519+ML-KEM-768 when available
- No PQ-specific wallet work needed until chains adopt PQ signatures

## Testing

### Unit Tests (run inside emu)

```sh
./emu/MacOSX/o.emu -r. -c0 /dis/tests/secp256k1_test.dis -v    # 11 tests
./emu/MacOSX/o.emu -r. -c0 /dis/tests/ethcrypto_test.dis -v    # 15 tests
./emu/MacOSX/o.emu -r. -c0 /dis/tests/x402_test.dis -v          # 9 tests
```

### Integration Tests (run on host)

```sh
bash tests/host/wallet9p_test.sh              # wallet9p basic operations
bash tests/host/wallet_e2e_test.sh            # Base Sepolia RPC connectivity
bash tests/host/secstore_logon_test.sh        # secstore + factotum persistence (10 tests)
bash tests/host/wallet_persist_test.sh        # wallet key survival across restarts (7 tests)
```

### Test Safety

All integration tests use dedicated test user accounts (`testuser-walletpersist`, `testuser-seclogon`). They never touch the real user's secstore data.

## Building

```sh
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH

# C crypto layer (requires emu rebuild)
cd libsec && mk install
cd ../libinterp && rm -f keyring.h keyringif.h && mk keyring.h && mk keyringif.h && mk install
cd ../emu/MacOSX && mk o.emu && cp o.emu InferNode

# Limbo libraries
limbo -I$ROOT/module -gw -o dis/lib/ethcrypto.dis appl/lib/ethcrypto.b
limbo -I$ROOT/module -gw -o dis/lib/wallet.dis appl/lib/wallet.b
limbo -I$ROOT/module -gw -o dis/lib/x402.dis appl/lib/x402.b
limbo -I$ROOT/module -gw -o dis/lib/stripe.dis appl/lib/stripe.b
limbo -I$ROOT/module -gw -o dis/lib/ethrpc.dis appl/lib/ethrpc.b

# 9P server and tools
limbo -I$ROOT/module -gw -o dis/veltro/wallet9p.dis appl/veltro/wallet9p.b
cd appl/veltro/tools && limbo -I$ROOT/module -I$ROOT/appl/veltro -gw \
    -o $ROOT/dis/veltro/tools/wallet.dis wallet.b
cd appl/veltro/tools && limbo -I$ROOT/module -I$ROOT/appl/veltro -gw \
    -o $ROOT/dis/veltro/tools/payfetch.dis payfetch.b

# GUI apps
limbo -I$ROOT/module -gw -o dis/wm/wallet.dis appl/wm/wallet.b
limbo -I$ROOT/module -gw -o dis/wm/logon.dis appl/wm/logon.b

# Widget toolkit (if widget.m changed, rebuild all GUI apps)
limbo -I$ROOT/module -gw -o dis/lib/widget.dis appl/lib/widget.b
```

## File Index

| File | Purpose |
|------|---------|
| `libsec/secp256k1.c` | secp256k1 ECDSA (C, constant-time) |
| `libsec/keccak256.c` | Keccak-256 hash (C) |
| `include/libsec.h` | C function declarations |
| `module/keyring.m` | Limbo crypto builtins |
| `libinterp/keyring.c` | C↔Limbo glue for crypto |
| `module/ethcrypto.m` | Ethereum crypto module interface |
| `appl/lib/ethcrypto.b` | RLP, EIP-155, EIP-712, addresses |
| `module/wallet.m` | Wallet library interface |
| `appl/lib/wallet.b` | Factotum-backed account management |
| `module/ethrpc.m` | Ethereum JSON-RPC client interface |
| `appl/lib/ethrpc.b` | JSON-RPC implementation |
| `module/x402.m` | x402 payment protocol interface |
| `appl/lib/x402.b` | x402 v2 implementation |
| `module/stripe.m` | Stripe API client interface |
| `appl/lib/stripe.b` | Stripe REST API implementation |
| `appl/veltro/wallet9p.b` | Wallet 9P file server |
| `appl/veltro/tools/wallet.b` | Veltro wallet tool |
| `appl/veltro/tools/payfetch.b` | x402-enabled HTTP fetch tool |
| `appl/wm/wallet.b` | Wallet GUI application |
| `appl/wm/logon.b` | Login/secstore unlock screen |
| `appl/cmd/auth/factotum/factotum.b` | Factotum with secstore ctl command |
| `module/widget.m` | Widget toolkit (includes Dropdown) |
| `appl/lib/widget.b` | Widget implementation |
| `lib/sh/profile` | Boot profile (secstored + factotum) |
| `lib/lucifer/login-screen.png` | Login screen brand image |
