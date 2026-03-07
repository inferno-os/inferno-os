# Quantum-Safe Cryptography Plan for Infernode

**Status:** Complete — All phases implemented (FIPS 203, 204, 205)
**Date:** 2026-03-05
**Predecessor:** [CRYPTO-MODERNIZATION.md](CRYPTO-MODERNIZATION.md) (Phases 1-5 complete)

### Implementation Status

| Phase | Component | Status |
|-------|-----------|--------|
| 0 | SHA-3/SHAKE (FIPS 202) | **Complete** |
| 1 | ML-KEM-768/1024 primitives (FIPS 203) | **Complete** |
| 2 | ML-KEM Keyring integration | **Complete** |
| 3 | Hybrid X25519+ML-KEM-768 TLS 1.3 | **Complete** |
| 4 | ML-DSA-65/87 primitives (FIPS 204) | **Complete** |
| 5 | ML-DSA Keyring/X.509 integration | **Complete** |
| 6 | Testing (SHA-3, ML-KEM, ML-DSA, TLS PQ) | **Complete** |
| 7 | SLH-DSA-SHAKE-192s/256s (FIPS 205) | **Complete** |
| 7 | SLH-DSA Keyring/X.509 integration | **Complete** |
| 7 | SHA-3 Keyring builtins | **Complete** |
| 7 | Comprehensive test hardening | **Complete** |
| 7 | Documentation | **Complete** |

All 8 SigAlgVec slots filled: ed25519, elgamal, rsa, dsa, mldsa65, mldsa87, slhdsa192s, slhdsa256s.

## 1. Motivation

Quantum computers capable of running Shor's algorithm will break RSA, DSA, ECDH, ECDSA, and ElGamal — all asymmetric algorithms currently used in Infernode. The **"harvest now, decrypt later"** threat means adversaries recording encrypted traffic today can decrypt it once they obtain a cryptographically relevant quantum computer (projected 5-10 years).

NIST finalized three post-quantum cryptography standards in August 2024:

| Standard | Algorithm | Purpose | Based On |
|----------|-----------|---------|----------|
| **FIPS 203** | ML-KEM (Kyber) | Key encapsulation | Module lattices (MLWE) |
| **FIPS 204** | ML-DSA (Dilithium) | Digital signatures | Module lattices (MLWE/MSIS) |
| **FIPS 205** | SLH-DSA (SPHINCS+) | Digital signatures | Hash-based (conservative backup) |

Additionally, **FIPS 206 (FN-DSA / FALCON)** is in development, and **HQC** was selected for standardization in March 2025 as an alternative KEM.

Industry adoption is accelerating: Chrome, Cloudflare, and major cloud providers already use hybrid X25519+ML-KEM-768 for TLS. NSA's CNSA 2.0 timeline requires PQ support in software by 2025 and exclusive PQ use by 2030-2033.

## 2. Design Decisions

### 2.1 Clean Break (Continuing Precedent)

Following the crypto modernization's "clean break" philosophy: PQ algorithms will be added as **new options**, not replacing classical algorithms. Hybrid constructions combine classical + PQ for defense-in-depth during the transition.

### 2.2 Native C Implementations

PQ primitives will be implemented in C within `libsec/`, following the existing pattern where all crypto primitives live (AES, ChaCha20, SHA-256, Ed25519, X25519, P-256, etc.). Protocol logic remains in Limbo.

**Source:** Adapt the `pq-code-package` reference implementations (`mlkem-native`, `mldsa-native`) — MIT/Apache-2.0/ISC licensed — to Plan 9 C conventions (`uchar`, `lib9.h` types). This follows the precedent of Ed25519 (adapted from SUPERCOP ref10) and the rest of `libsec/` (adapted from Plan 9).

### 2.3 Parameter Sets

Implement with parameterized lattice dimension `k`, expose two security levels per algorithm:

| Algorithm | Level 3 (Recommended) | Level 5 (Maximum) |
|-----------|-----------------------|-------------------|
| ML-KEM | **ML-KEM-768** | ML-KEM-1024 |
| ML-DSA | **ML-DSA-65** | ML-DSA-87 |

Level 1/2 parameter sets (ML-KEM-512, ML-DSA-44) are omitted — below the security threshold for long-term use. Adding them later requires only new constants and wrapper functions since the core NTT/polynomial arithmetic is shared.

### 2.4 Hybrid-First

All PQ deployments use hybrid constructions pairing PQ with classical:
- **TLS key exchange:** X25519 + ML-KEM-768 (combined shared secret)
- **Certificates:** Classical Ed25519 remains for now; ML-DSA available as alternative; dual-signature certificates are a future option

### 2.5 Priority Order

ML-KEM first (addresses harvest-now-decrypt-later), then ML-DSA (addresses future forgery).

## 3. Current Crypto Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Applications (auth tools, Veltro, services, httpd)     │
├─────────────────────────────────────────────────────────┤
│  Protocols (Limbo)                                      │
│    tls.b  ─ TLS 1.2/1.3 handshake                      │
│    ssl3.b ─ SSL 3.0 (legacy)                            │
│    x509.b ─ Certificate parsing/validation              │
│    pkcs.b ─ PKCS encoding/decoding                      │
│    auth.b ─ Station-to-Station mutual auth              │
├─────────────────────────────────────────────────────────┤
│  Keyring Module (keyring.m ↔ keyring.c)                 │
│    SigAlgVec: ed25519, rsa, dsa, elgamal (4/8 slots)   │
│    Builtins: x25519, p256_ecdh/ecdsa, ed25519_sign     │
│    ADTs: PK, SK, Certificate, SigAlg (generic)          │
│    ADTs: RSApk/sk/sig, DSApk/sk/sig, EGpk/sk/sig       │
├─────────────────────────────────────────────────────────┤
│  C Primitives                                           │
│    libsec/  ─ AES, ChaCha20, SHA-*, DES, Blowfish      │
│    libkeyring/ ─ ed25519alg.c, rsaalg.c, dsaalg.c      │
│    libmp/   ─ Big integer arithmetic (IPint)            │
└─────────────────────────────────────────────────────────┘
```

### Key Integration Points

1. **`SigAlgVec` array** (`libinterp/keyring.c`): `algs[Maxalg]` with Maxalg=8, currently 4 used. Each algorithm implements: `init`, `gensk`, `sk2pk`, `sign`, `verify`, `sktostr/pktostr/sigtostr`, `strtosk/strtopk/strtosig`. Pattern: `libkeyring/ed25519alg.c`.

2. **Builtin KEM/ECDH functions** (`libinterp/keyring.c`): `x25519()`, `x25519_base()`, `p256_keygen()`, `p256_ecdh()` use raw byte arrays (not SigAlgVec). ML-KEM follows this pattern.

3. **TLS named groups** (`appl/lib/crypt/tls.b`): `GROUP_X25519 = 0x001D`, `GROUP_SECP256R1 = 0x0017`. Key share extension builds/parses group-specific data in `buildkeyshare()`/`parseserverhello()`.

4. **X.509 AlgorithmIdentifier** (`appl/lib/crypt/x509.b`, `pkcs.b`): OID-based algorithm dispatch for certificate signature verification.

## 4. SHA-3 / SHAKE Prerequisite

Both ML-KEM and ML-DSA require SHAKE-128 and SHAKE-256 (extendable output functions based on Keccak). Infernode currently has SHA-1/SHA-256/SHA-384/SHA-512 but **no SHA-3 family**.

### Phase 0: SHA-3 / SHAKE Implementation

**New files:**
- `libsec/sha3.c` — Keccak-f[1600] permutation, SHA3-256, SHA3-512, SHAKE-128, SHAKE-256

**Interface** (add to `include/libsec.h`):
```c
/* SHA-3 / SHAKE (FIPS 202) */
typedef struct SHA3state SHA3state;
struct SHA3state {
    uvlong a[25];       /* Keccak state (5x5 x 64-bit) */
    uchar  buf[200];    /* rate buffer */
    int    rate;        /* rate in bytes */
    int    pt;          /* buffer position */
    int    mdlen;       /* output length (0 for XOF) */
};

void  sha3_256(uchar *in, ulong inlen, uchar out[32]);
void  sha3_512(uchar *in, ulong inlen, uchar out[64]);

/* SHAKE extendable-output functions */
void  shake128_init(SHA3state *s);
void  shake128_absorb(SHA3state *s, uchar *in, ulong inlen);
void  shake128_squeeze(SHA3state *s, uchar *out, ulong outlen);

void  shake256_init(SHA3state *s);
void  shake256_absorb(SHA3state *s, uchar *in, ulong inlen);
void  shake256_squeeze(SHA3state *s, uchar *out, ulong outlen);

/* Convenience: absorb + finalize in one call */
void  shake128(uchar *in, ulong inlen, uchar *out, ulong outlen);
void  shake256(uchar *in, ulong inlen, uchar *out, ulong outlen);
```

**Modify:**
- `include/libsec.h` — Add SHA3/SHAKE declarations above
- `libsec/mkfile` — Add `sha3.c` to OFILES

**Testing:** NIST SHA-3 test vectors (CAVP), SHAKE known-answer tests.

**Implementation notes:**
- Keccak-f[1600] is ~200 lines of C (24 rounds of theta/rho/pi/chi/iota)
- Constant-time by construction (no data-dependent branches or table lookups)
- Can later add ARM64 NEON optimizations if needed

## 5. Phase 1: ML-KEM-768 / ML-KEM-1024 Primitives

**Goal:** Implement FIPS 203 ML-KEM in portable C.

### Parameter Sets

| Parameter | ML-KEM-768 | ML-KEM-1024 |
|-----------|-----------|-------------|
| Lattice dimension (k) | 3 | 4 |
| Modulus (q) | 3329 | 3329 |
| Public key | 1184 bytes | 1568 bytes |
| Secret key | 2400 bytes | 3168 bytes |
| Ciphertext | 1088 bytes | 1568 bytes |
| Shared secret | 32 bytes | 32 bytes |
| Security | NIST Level 3 | NIST Level 5 |

### New Files

**`libsec/mlkem.c`** — Core ML-KEM operations:
```c
/* ML-KEM key sizes */
enum {
    /* ML-KEM-768 */
    MLKEM768_PKLEN  = 1184,
    MLKEM768_SKLEN  = 2400,
    MLKEM768_CTLEN  = 1088,

    /* ML-KEM-1024 */
    MLKEM1024_PKLEN = 1568,
    MLKEM1024_SKLEN = 3168,
    MLKEM1024_CTLEN = 1568,

    /* Common */
    MLKEM_SSLEN     = 32,
    MLKEM_Q         = 3329,
};

/* ML-KEM-768 */
int mlkem768_keygen(uchar *pk, uchar *sk);
int mlkem768_encaps(uchar *ct, uchar *ss, const uchar *pk);
int mlkem768_decaps(uchar *ss, const uchar *ct, const uchar *sk);

/* ML-KEM-1024 */
int mlkem1024_keygen(uchar *pk, uchar *sk);
int mlkem1024_encaps(uchar *ct, uchar *ss, const uchar *pk);
int mlkem1024_decaps(uchar *ss, const uchar *ct, const uchar *sk);
```

**`libsec/mlkem_ntt.c`** — Number Theoretic Transform (mod q=3329):
- Forward/inverse NTT (butterfly operations)
- Barrett reduction
- Montgomery multiplication
- Polynomial multiply via NTT: `poly_basemul()`
- Shared across all parameter sets

**`libsec/mlkem_poly.c`** — Polynomial and vector operations:
- Centered Binomial Distribution (CBD) sampling
- Rejection sampling from SHAKE-128 for matrix A
- Compress/decompress functions
- Encode/decode for serialization
- `cpapke_keypair()`, `cpapke_enc()`, `cpapke_dec()` (inner PKE)

### Modified Files
- `include/libsec.h` — Add ML-KEM declarations
- `libsec/mkfile` — Add new source files

### Implementation Requirements
- **Constant-time**: No data-dependent branches, no variable-time array indexing
- **No dynamic allocation**: Fixed-size stack buffers (max ~3168 bytes for SK-1024)
- **FIPS 203 compliance**: Must pass NIST KAT vectors
- **Zeroization**: Clear secret key material from stack on function exit

## 6. Phase 2: ML-KEM Keyring Integration

**Goal:** Expose ML-KEM operations to Limbo via the Keyring module.

### Module Interface

**Modify `module/keyring.m`** — Add KEM constants and functions:
```limbo
# ML-KEM-768 (FIPS 203, NIST Level 3)
MLKEM768_PKLEN:  con 1184;
MLKEM768_SKLEN:  con 2400;
MLKEM768_CTLEN:  con 1088;

# ML-KEM-1024 (FIPS 203, NIST Level 5)
MLKEM1024_PKLEN: con 1568;
MLKEM1024_SKLEN: con 3168;
MLKEM1024_CTLEN: con 1568;

MLKEM_SSLEN:     con 32;

# ML-KEM key encapsulation operations
mlkem768_keygen:  fn(): (array of byte, array of byte);
mlkem768_encaps:  fn(pk: array of byte): (array of byte, array of byte);
mlkem768_decaps:  fn(sk: array of byte, ct: array of byte): array of byte;

mlkem1024_keygen: fn(): (array of byte, array of byte);
mlkem1024_encaps: fn(pk: array of byte): (array of byte, array of byte);
mlkem1024_decaps: fn(sk: array of byte, ct: array of byte): array of byte;
```

### C Bridge

**Modify `libinterp/keyring.c`** — Add builtin implementations:

```c
// Pattern follows x25519/p256_ecdh: raw byte array interface
void Keyring_mlkem768_keygen(void *fp);
void Keyring_mlkem768_encaps(void *fp);
void Keyring_mlkem768_decaps(void *fp);
void Keyring_mlkem1024_keygen(void *fp);
void Keyring_mlkem1024_encaps(void *fp);
void Keyring_mlkem1024_decaps(void *fp);
```

Each function:
1. Extracts arguments from the Dis frame pointer
2. Allocates byte arrays via `H2D`/`mem2array`
3. Calls the corresponding `libsec/mlkem.c` function
4. Returns results (pk/sk tuple for keygen, ct/ss tuple for encaps, ss for decaps)
5. Zeros secret material after use

### Why Not SigAlgVec?

ML-KEM is a **key encapsulation mechanism**, not a signature algorithm. The `SigAlgVec` interface (`gensk`/`sign`/`verify`) doesn't fit. Raw builtin functions (like `x25519`/`p256_ecdh`) are the correct pattern.

## 7. Phase 3: Hybrid X25519+ML-KEM-768 in TLS 1.3

**Goal:** Add hybrid post-quantum key exchange per `draft-ietf-tls-ecdhe-mlkem-04`.

### TLS Named Group

**Modify `module/tls.m` and `appl/lib/crypt/tls.b`:**
```limbo
# Post-quantum hybrid (IANA registered)
GROUP_X25519MLKEM768: con 16r4588;
```

### Handshake Changes

**Client Hello** (`buildclienthello` / `buildkeyshare` in `tls.b`):

1. Generate ML-KEM-768 keypair: `(ek, dk) := keyring->mlkem768_keygen()`
2. Generate X25519 keypair: `x25519_priv := randombytes(32); x25519_pub := keyring->x25519_base(x25519_priv)`
3. Build key_share entry for `GROUP_X25519MLKEM768`:
   - Encode: `ek (1184 bytes) || x25519_pub (32 bytes)` = **1216 bytes**
4. Also include `GROUP_X25519` key share as fallback
5. Send `supported_groups` with `X25519MLKEM768` listed first

**Server Hello parsing** (`parseserverhello` in `tls.b`):

If server selects `GROUP_X25519MLKEM768`:
1. Parse server key_share: `ct (1088 bytes) || x25519_server (32 bytes)` = **1120 bytes**
2. Derive PQ shared secret: `ss_pq := keyring->mlkem768_decaps(dk, ct)`
3. Derive classical shared secret: `ss_classical := keyring->x25519(x25519_priv, x25519_server)`
4. Combined shared secret: `ss := ss_pq || ss_classical` (64 bytes total, fed to HKDF)

If server selects `GROUP_X25519`:
1. Fall back to classical-only X25519 (existing code path, no changes needed)

### Wire Format

```
Client key_share for X25519MLKEM768:
  ┌─────────────────────────┬──────────────┐
  │ ML-KEM-768 ek (1184 B)  │ X25519 (32B) │
  └─────────────────────────┴──────────────┘

Server key_share for X25519MLKEM768:
  ┌─────────────────────────┬──────────────┐
  │ ML-KEM-768 ct (1088 B)  │ X25519 (32B) │
  └─────────────────────────┴──────────────┘

Shared secret derivation:
  ss_pq (32B) || ss_classical (32B) → HKDF-Extract → handshake keys
```

### Backward Compatibility

- Servers that don't support PQ select `GROUP_X25519` from the fallback — **zero breakage**
- The hybrid group is preferred (listed first) but not required
- Cipher suites are orthogonal to key exchange — AES-256-GCM and ChaCha20-Poly1305 work with either
- Client Hello grows by ~1.2KB (key_share for ML-KEM), well within typical MTU

### Key Code Changes in `tls.b`

| Function | Change |
|----------|--------|
| `buildclienthello()` | Generate ML-KEM keypair, add hybrid key share |
| `buildkeyshare()` | Encode 1216-byte hybrid key share |
| `parseserverhello()` | Handle GROUP_X25519MLKEM768 selection |
| `handshake13()` | Hybrid shared secret derivation path |
| `handshake12()` | No changes (TLS 1.2 doesn't support PQ groups) |
| Group constants | Add `GROUP_X25519MLKEM768: con 16r4588` |
| Supported groups extension | Add `X25519MLKEM768` first in list |

## 8. Phase 4: ML-DSA-65 / ML-DSA-87 Primitives

**Goal:** Implement FIPS 204 ML-DSA in portable C.

### Parameter Sets

| Parameter | ML-DSA-65 | ML-DSA-87 |
|-----------|-----------|-----------|
| Lattice (k, l) | (6, 5) | (8, 7) |
| Modulus (q) | 8380417 | 8380417 |
| Public key | 1952 bytes | 2592 bytes |
| Secret key | 4032 bytes | 4896 bytes |
| Signature | 3309 bytes | 4627 bytes |
| Security | NIST Level 3 | NIST Level 5 |

### New Files

**`libsec/mldsa.c`** — Core ML-DSA operations:
```c
enum {
    /* ML-DSA-65 */
    MLDSA65_PKLEN  = 1952,
    MLDSA65_SKLEN  = 4032,
    MLDSA65_SIGLEN = 3309,

    /* ML-DSA-87 */
    MLDSA87_PKLEN  = 2592,
    MLDSA87_SKLEN  = 4896,
    MLDSA87_SIGLEN = 4627,

    MLDSA_Q        = 8380417,
};

int mldsa65_keygen(uchar *pk, uchar *sk);
int mldsa65_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk);
int mldsa65_verify(const uchar *sig, const uchar *msg, ulong msglen, const uchar *pk);

int mldsa87_keygen(uchar *pk, uchar *sk);
int mldsa87_sign(uchar *sig, const uchar *msg, ulong msglen, const uchar *sk);
int mldsa87_verify(const uchar *sig, const uchar *msg, ulong msglen, const uchar *pk);
```

**`libsec/mldsa_ntt.c`** — NTT for ML-DSA (q=8380417):
- Different modulus from ML-KEM (q=3329), so separate NTT implementation
- Same structure: forward/inverse NTT, Barrett/Montgomery reduction, basemul

**`libsec/mldsa_poly.c`** — ML-DSA polynomial operations:
- ExpandA (SHAKE-128), ExpandS, ExpandMask (SHAKE-256)
- Bit-packing/unpacking for keys and signatures
- MakeHint / UseHint for signature compression
- HighBits / LowBits decomposition

### Shared Infrastructure
- `libsec/sha3.c` — SHAKE-128/256 already from Phase 0
- Structural patterns from ML-KEM NTT can guide implementation

### Modified Files
- `include/libsec.h` — Add ML-DSA declarations
- `libsec/mkfile` — Add new source files

## 9. Phase 5: ML-DSA Integration

### 5a: Keyring SigAlgVec Registration

**New file `libkeyring/mldsaalg.c`** — Following `ed25519alg.c` pattern:

```c
/* ML-DSA key structures (opaque to Limbo, stored in Keyring PK/SK) */
typedef struct MLDSApriv MLDSApriv;
typedef struct MLDSApub  MLDSApub;
typedef struct MLDSAsig_ MLDSAsig_;

struct MLDSApriv {
    uchar sk[MLDSA65_SKLEN];   /* 4032 bytes */
    uchar pk[MLDSA65_PKLEN];   /* 1952 bytes (for convenience) */
    int   level;               /* 65 or 87 */
};

struct MLDSApub {
    uchar key[MLDSA65_PKLEN];  /* 1952 bytes (or 2592 for level 87) */
    int   level;
};

struct MLDSAsig_ {
    uchar sig[MLDSA65_SIGLEN]; /* 3309 bytes (or 4627 for level 87) */
    int   level;
};

/* SigAlgVec interface */
static SigAlgVec mldsa65vec = {
    "mldsa65",
    mldsa_sk2pk,
    mldsa65_gensk,
    mldsa_sign,
    mldsa_verify,
    mldsa_sktostr,
    mldsa_pktostr,
    mldsa_strtosk,
    mldsa_strtopk,
    mldsa_sigtostr,
    mldsa_strtosig,
};

static SigAlgVec mldsa87vec = {
    "mldsa87",
    ...  /* same functions, different parameters */
};

SigAlgVec* mldsa65init(void);
SigAlgVec* mldsa87init(void);
```

**Modify `libinterp/keyring.c`:**
```c
// In keyringmodinit(), after existing algorithm registrations:
extern SigAlgVec* mldsa65init(void);
extern SigAlgVec* mldsa87init(void);
if((sav = mldsa65init()) != nil) algs[nalg++] = sav;  // slot 5
if((sav = mldsa87init()) != nil) algs[nalg++] = sav;  // slot 6
// Still 2 slots remaining in algs[8]
```

**Modify `libkeyring/keys.h`:**
```c
extern SigAlgVec* mldsa65init(void);
extern SigAlgVec* mldsa87init(void);
```

**Usage from Limbo** (no changes to `keyring.m` needed for generic SigAlgVec):
```limbo
# Generate ML-DSA-65 key pair
sk := keyring->genSK("mldsa65", "alice", 0);
pk := keyring->sktopk(sk);

# Sign a message
state := keyring->sha256(msg, len msg, nil, nil);
cert := keyring->sign(sk, expiry, state, "sha256");

# Verify
valid := keyring->verify(pk, cert, state);
```

### 5b: X.509 Certificate Support

**Modify `appl/lib/crypt/x509.b`:**
- Add OID `id-ML-DSA-65`: `2.16.840.1.101.3.4.3.18`
- Add OID `id-ML-DSA-87`: `2.16.840.1.101.3.4.3.19`
- Handle ML-DSA public keys in `SubjectPublicKeyInfo` parsing
- Handle ML-DSA signatures in `AlgorithmIdentifier` dispatch
- Certificate verification path: detect ML-DSA OID → extract raw pub key → call `keyring->verifym()` or internal verify

**Modify `module/x509.m`:**
```limbo
# Add to public key type constants
PKtype_mldsa65: con 5;
PKtype_mldsa87: con 6;
```

**Modify `appl/lib/crypt/pkcs.b`:**
- Add ML-DSA OIDs to algorithm identifier table
- Map OID to algorithm name for certificate processing

### 5c: Auth Tool Updates

**Modify `appl/cmd/auth/createsignerkey.b`:**
- Add `mldsa65` and `mldsa87` to algorithm selection
- ML-DSA-65 as a recommended PQ option

**New `appl/cmd/auth/mldsagen.b`** (optional convenience command):
- Standalone ML-DSA key generation (like `rsagen.b`)
- Outputs key in standard Inferno key format

## 10. Phase 6: Testing

### New Test Files

**`tests/sha3_test.b`** — SHA-3/SHAKE:
- SHA3-256 and SHA3-512 NIST test vectors
- SHAKE-128 and SHAKE-256 known-answer tests
- Empty input, short input, long input vectors

**`tests/mlkem_test.b`** — ML-KEM:
- Keygen produces valid keys (correct sizes)
- Encaps/decaps round-trip: shared secrets match
- ML-KEM-768 and ML-KEM-1024 parameter sets
- NIST FIPS 203 KAT vectors
- Invalid ciphertext handling (decaps returns random-looking output, per spec)
- Key size validation

**`tests/mldsa_test.b`** — ML-DSA:
- Keygen produces valid keys
- Sign/verify round-trip
- ML-DSA-65 and ML-DSA-87 parameter sets
- NIST FIPS 204 KAT vectors
- Invalid signature rejection
- Wrong-key rejection
- Integration with Keyring generic `sign()`/`verify()` via SigAlgVec
- Certificate generation and verification with ML-DSA

**`tests/tls_pq_test.b`** — TLS hybrid:
- X25519MLKEM768 key share encoding/decoding
- Hybrid shared secret derivation
- Fallback to X25519 when server doesn't support PQ
- Group negotiation preference order

### Extend Existing Tests

**`tests/crypto_test.b`** — Add ML-KEM and ML-DSA cases alongside existing Ed25519 tests.

### Formal Verification Extensions

**`formal-verification/`** — Add CBMC harnesses:
- Buffer bounds checking for ML-KEM/ML-DSA key/signature buffers
- Constant-time verification of NTT operations
- Memory safety of polynomial arithmetic

### Test Execution

```sh
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH

# Build tests
cd tests && mk install

# Run individual test suites
./emu/MacOSX/o.emu -r. /tests/sha3_test.dis
./emu/MacOSX/o.emu -r. /tests/mlkem_test.dis
./emu/MacOSX/o.emu -r. /tests/mldsa_test.dis
./emu/MacOSX/o.emu -r. /tests/tls_pq_test.dis

# Run all tests (regression)
./emu/MacOSX/o.emu -r. /tests/runner.dis
```

### Interoperability Testing

- TLS hybrid handshake against Cloudflare (supports X25519MLKEM768)
- TLS hybrid handshake against Google (supports X25519MLKEM768)
- ML-DSA certificate verification against OpenSSL 3.5+ generated certs

## 11. Phase 7: Documentation and Migration

### Update `docs/CRYPTO-MODERNIZATION.md`
- Add PQ crypto section
- Remove PQ from "Future Work" list
- Document hybrid TLS configuration

### Update migration guide
- How to generate ML-DSA signer keys: `auth/createsignerkey -a mldsa65`
- How to verify PQ TLS is working (check negotiated group)
- Recommendation: enable hybrid TLS immediately (zero-risk upgrade with classical fallback)

## 12. Implementation Dependencies and Order

```
                    ┌──────────────┐
                    │ Phase 0      │
                    │ SHA-3/SHAKE  │
                    │ libsec/sha3.c│
                    └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
      ┌───────────────┐        ┌───────────────┐
      │ Phase 1       │        │ Phase 4       │
      │ ML-KEM-768    │        │ ML-DSA-65     │
      │ ML-KEM-1024   │        │ ML-DSA-87     │
      │ libsec/mlkem* │        │ libsec/mldsa* │
      └───────┬───────┘        └───────┬───────┘
              │                        │
              ▼                        ▼
      ┌───────────────┐        ┌───────────────┐
      │ Phase 2       │        │ Phase 5       │
      │ ML-KEM in     │        │ ML-DSA in     │
      │ Keyring       │        │ Keyring/X.509 │
      └───────┬───────┘        └───────┬───────┘
              │                        │
              ▼                        │
      ┌───────────────┐                │
      │ Phase 3       │                │
      │ Hybrid TLS    │                │
      │ X25519MLKEM768│                │
      └───────┬───────┘                │
              │                        │
              └──────────┬─────────────┘
                         ▼
                 ┌───────────────┐
                 │ Phase 6       │
                 │ Testing       │
                 │ (incremental) │
                 └───────┬───────┘
                         ▼
                 ┌───────────────┐
                 │ Phase 7       │
                 │ Documentation │
                 └───────────────┘
```

**Note:** Phases 1-3 (ML-KEM path) and Phases 4-5 (ML-DSA path) can proceed in parallel after Phase 0. Testing (Phase 6) is incremental — each phase should include its own tests. Phase 7 is final documentation.

## 13. File Summary

### New Files (13)

| File | Phase | Purpose |
|------|-------|---------|
| `libsec/sha3.c` | 0 | Keccak, SHA3-256/512, SHAKE-128/256 |
| `libsec/mlkem.c` | 1 | ML-KEM-768/1024 keygen/encaps/decaps |
| `libsec/mlkem_ntt.c` | 1 | NTT arithmetic mod q=3329 |
| `libsec/mlkem_poly.c` | 1 | Polynomial/matrix operations, CBD, compression |
| `libsec/mldsa.c` | 4 | ML-DSA-65/87 keygen/sign/verify |
| `libsec/mldsa_ntt.c` | 4 | NTT arithmetic mod q=8380417 |
| `libsec/mldsa_poly.c` | 4 | Polynomial packing, hint, decomposition |
| `libkeyring/mldsaalg.c` | 5 | ML-DSA SigAlgVec implementation |
| `tests/sha3_test.b` | 6 | SHA-3/SHAKE test vectors |
| `tests/mlkem_test.b` | 6 | ML-KEM round-trip and KAT tests |
| `tests/mldsa_test.b` | 6 | ML-DSA round-trip and KAT tests |
| `tests/tls_pq_test.b` | 6 | Hybrid TLS handshake tests |
| `appl/cmd/auth/mldsagen.b` | 5 | ML-DSA key generation command (optional) |

### Modified Files (13)

| File | Phase | Change |
|------|-------|--------|
| `include/libsec.h` | 0,1,4 | SHA3/SHAKE, ML-KEM, ML-DSA declarations |
| `libsec/mkfile` | 0,1,4 | Add new source files |
| `module/keyring.m` | 2 | ML-KEM constants and function declarations |
| `libinterp/keyring.c` | 2,5 | ML-KEM builtins, ML-DSA algorithm registration |
| `module/tls.m` | 3 | X25519MLKEM768 named group constant |
| `appl/lib/crypt/tls.b` | 3 | Hybrid key exchange in TLS 1.3 handshake |
| `libkeyring/keys.h` | 5 | ML-DSA init declarations |
| `libkeyring/mkfile` | 5 | Add mldsaalg.c |
| `appl/lib/crypt/x509.b` | 5 | ML-DSA OIDs and cert verification |
| `module/x509.m` | 5 | ML-DSA public key type constants |
| `appl/lib/crypt/pkcs.b` | 5 | ML-DSA OIDs in algorithm table |
| `appl/cmd/auth/createsignerkey.b` | 5 | ML-DSA algorithm option |
| `docs/CRYPTO-MODERNIZATION.md` | 7 | PQ crypto documentation |

## 14. Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Side-channel attacks on NTT | Constant-time implementation; no secret-dependent branches/indexing |
| Large key/signature sizes | ML-KEM-768 adds ~1.2KB to TLS ClientHello; within MTU limits |
| Specification changes | FIPS 203/204 are finalized; interface is stable |
| Reference code bugs | Validate against full NIST KAT vector sets; formal verification via CBMC |
| Performance on embedded | ML-KEM-768 is ~150μs on modern CPUs; ML-DSA-65 is faster than RSA-2048 |
| Maxalg overflow in keyring.c | Currently 4/8 slots used; adding 2 ML-DSA variants uses 6/8; 2 slots remain |

## 15. References

- [NIST FIPS 203 (ML-KEM)](https://csrc.nist.gov/pubs/fips/203/final) — Finalized August 2024
- [NIST FIPS 204 (ML-DSA)](https://csrc.nist.gov/pubs/fips/204/final) — Finalized August 2024
- [NIST FIPS 205 (SLH-DSA)](https://csrc.nist.gov/pubs/fips/205/final) — Finalized August 2024
- [NIST PQC Standards Announcement](https://www.nist.gov/news-events/news/2024/08/nist-releases-first-3-finalized-post-quantum-encryption-standards)
- [draft-ietf-tls-ecdhe-mlkem](https://datatracker.ietf.org/doc/draft-ietf-tls-ecdhe-mlkem/) — Hybrid TLS key exchange
- [pq-code-package (mlkem-native, mldsa-native)](https://github.com/pq-code-package) — Reference implementations (MIT/Apache/ISC)
- [Open Quantum Safe — ML-KEM](https://openquantumsafe.org/liboqs/algorithms/kem/ml-kem.html)
- [Open Quantum Safe — ML-DSA](https://openquantumsafe.org/liboqs/algorithms/sig/ml-dsa.html)
- [CSA: FIPS 203/204/205 Finalized](https://cloudsecurityalliance.org/blog/2024/08/15/nist-fips-203-204-and-205-finalized-an-important-step-towards-a-quantum-safe-future)
- [Palo Alto Networks PQC Guide](https://www.paloaltonetworks.com/cyberpedia/pqc-standards)
- [PQShield 2025 Whitepaper](https://pqshield.com/updated-whitepaper-for-2025-the-new-nist-standards-are-here-what-does-it-mean-for-pqc-in-2025/)
