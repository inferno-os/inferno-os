# Cryptographic Modernization Summary

**Status:** Complete (Phase 1-5 + ElGamal fix + Post-Quantum FIPS 203/204/205)

This document summarizes the cryptographic modernization work done on Inferno/infernode to support autonomous agent systems requiring identity verification and non-repudiation.

## Design Decision

**Clean break approach** - No backward compatibility with weak crypto. All deployments must regenerate keys after updating.

## Changes Implemented

### 1. Ed25519 Signatures (Phase 3)

Ed25519 is now the default signature algorithm for all new keys.

| Aspect | Before | After |
|--------|--------|-------|
| Default algorithm | ElGamal | **Ed25519** |
| Key size | 256+ bytes | 32 bytes |
| Signature size | Variable | 64 bytes |
| Performance | Slow keygen | Instant keygen |

**Files modified:**
- `libkeyring/ed25519alg.c` (new) - Ed25519 implementation
- `libkeyring/ed25519.c` (new) - Core Ed25519 operations
- `appl/cmd/auth/signer.b` - Uses Ed25519 by default
- `appl/cmd/auth/createsignerkey.b` - Ed25519 first in algorithm list

### 2. SHA-256 for Certificates (Phase 2)

All certificate hashing now uses SHA-256 instead of SHA-1.

| Aspect | Before | After |
|--------|--------|-------|
| Certificate hash | SHA-1 (broken) | **SHA-256** |
| Password hash | SHA-1 | **SHA-256** |
| Protocol digest | Mixed | **SHA-256** |

**Files modified:**
- `appl/cmd/auth/signer.b` - SHA-256 for signing
- `appl/cmd/auth/createsignerkey.b` - SHA-256 for certificates
- `appl/cmd/auth/logind.b` - SHA-256 for protocol
- `appl/cmd/auth/mkauthinfo.b` - SHA-256 for certificates
- `appl/cmd/auth/changelogin.b` - SHA-256 for passwords
- `appl/cmd/auth/keysrv.b` - SHA-256 for secret hashing
- `appl/lib/login.b` - SHA-256 for protocol

### 3. Key Size Defaults (Phase 1)

Minimum key sizes increased to 2048 bits.

| Component | Before | After |
|-----------|--------|-------|
| Signer PKmodlen | 512 bits | **2048 bits** |
| Signer DHmodlen | 512 bits | **2048 bits** |
| User PKmodlen | 1024 bits | **2048 bits** |
| User DHmodlen | 1024 bits | **2048 bits** |

**Files modified:**
- `appl/cmd/auth/signer.b` - 2048-bit defaults
- `appl/cmd/auth/createsignerkey.b` - 2048-bit defaults

### 4. ElGamal Performance Fix

ElGamal 2048-bit key generation improved from 8 minutes to 2 seconds (215x speedup).

| Metric | Before | After |
|--------|--------|-------|
| 2048-bit keygen | 486,000 ms | **2,258 ms** |
| Speedup | - | **215x** |

**Solution:** Pre-computed RFC 3526 MODP Group 14 parameters.

**Files modified:**
- `libsec/dhparams.c` (new) - RFC 3526 parameters
- `libsec/eggen.c` - Uses pre-computed params when available
- `include/libsec.h` - `getdhparams()` declaration
- `libsec/mkfile` - Build dhparams.c

## Security Properties

After these changes:

- **Signatures:** Ed25519 provides 128-bit security with deterministic signatures
- **Certificates:** SHA-256 hash prevents collision attacks
- **Key exchange:** 2048-bit DH provides ~112-bit security
- **Login EKE:** ChaCha20-Poly1305 AEAD with 256-bit key (replaces RC4-40)
- **SSL3 negotiation:** Weak ciphers rejected during handshake (no downgrade)
- **Revocation:** CRL-based certificate revocation checking
- **Transport:** WireGuard + Rosenpass handles (external to Inferno)

### 5. Login Protocol: RC4 → ChaCha20-Poly1305 (Phase 4)

The login EKE protocol's temporary encryption of the DH exchange now uses ChaCha20-Poly1305 AEAD instead of RC4-40.

| Aspect | Before | After |
|--------|--------|-------|
| Cipher | RC4-40 (40-bit key) | **ChaCha20-Poly1305 AEAD** |
| Key derivation | SHA-256 folded to 8 bytes | **SHA-256(SHA-256(pw) \|\| salt)** = 32 bytes |
| Authentication | None | **Poly1305 tag (16 bytes)** |
| IV/Nonce | 8-byte IV | **32 bytes (20 salt + 12 nonce)** |

**Files modified:**
- `appl/lib/login.b` - Client-side AEAD encryption
- `appl/cmd/auth/logind.b` - Server-side AEAD encryption

**Breaking change:** Clients and servers must both be updated. Old clients cannot authenticate with new servers and vice versa.

### 6. SSL3 Weak Cipher Suite Rejection (Phase 5)

Weak cipher suites are now rejected during SSL3 negotiation before selection, rather than failing late during cipher activation.

**Blocked categories:**
- NULL ciphers (no encryption)
- RC4 (biased output, practical attacks)
- DES / DES-40 (56-bit or 40-bit keys, trivially brute-forced)
- Export-grade ciphers (intentionally weakened)
- Anonymous key exchange (no server authentication)
- FORTEZZA (unsupported)

**Remaining allowed suites:** 3DES-EDE-CBC and IDEA-CBC with RSA/DH/DHE key exchange and SHA-1 MAC.

**Files modified:**
- `appl/lib/crypt/ssl3.b` - Added `is_weak_suite()` filter in `find_cipher_suite()`

### 7. Certificate Revocation Lists (Phase 5)

X.509 certificate verification now checks CRLs loaded from `/lib/crls/*.der`.

| Aspect | Before | After |
|--------|--------|-------|
| Revocation checking | None | **CRL-based** |
| CRL store | N/A | **`/lib/crls/*.der`** (DER-encoded CRLs) |
| Check point | N/A | **During `verify_certpath()`** |

**Files modified:**
- `appl/lib/crypt/x509.b` - CRL store loading and revocation checking in cert path validation
- `lib/crls/` - New directory for CRL DER files

## What's Not Changed

### HMAC-SHA1 in SSL3

SHA-1 usage in HMAC contexts remains (HMAC-SHA1 is still considered secure; the attacks on SHA-1 are collision attacks, not applicable to HMAC).

## Migration Guide

### For Existing Deployments

1. **Regenerate all keys:**
   ```sh
   # Generate new signer key with Ed25519
   auth/createsignerkey -a ed25519 signer_name

   # Recreate user accounts
   auth/changelogin username
   ```

2. **Update client certificates:**
   - Old certificates will fail verification (SHA-1 vs SHA-256)
   - Clients must re-authenticate to get new certificates

3. **Update all clients and servers together:**
   - Login protocol now uses ChaCha20-Poly1305 AEAD (incompatible with RC4 version)
   - Both `login.b` (client) and `logind.b` (server) must be updated simultaneously

4. **Install CRLs (optional):**
   - Place DER-encoded CRL files in `/lib/crls/` for revocation checking
   - CRLs are matched by issuer name against certificate issuers

### For New Deployments

No action needed - Ed25519, SHA-256, and AEAD login are the defaults.

## Testing

### Ed25519

```sh
# Run Ed25519 test in Inferno
/tests/ed25519_test.dis
```

### ElGamal Performance

```sh
# Run keygen benchmark
/tests/keygen_benchmark.dis
```

## Related Documentation

- [QUANTUM-SAFE-CRYPTO-PLAN.md](QUANTUM-SAFE-CRYPTO-PLAN.md) - Full PQ crypto design document
- [CRYPTO-DEBUGGING-GUIDE.md](CRYPTO-DEBUGGING-GUIDE.md) - Debugging methodology
- [ELGAMAL-PERFORMANCE.md](ELGAMAL-PERFORMANCE.md) - Detailed performance analysis

## Commits

- `850e906a` - feat(crypto): Add Ed25519 signatures and modernize cryptography
- `172d7f7f` - Add RFC 3526 pre-computed DH params for fast ElGamal 2048-bit keygen

### 8. Post-Quantum Cryptography (FIPS 203/204)

Native implementations of NIST post-quantum standards, with no external dependencies.

#### ML-KEM (FIPS 203) — Key Encapsulation

| Parameter Set | Security Level | Public Key | Secret Key | Ciphertext | Shared Secret |
|---------------|---------------|------------|------------|------------|---------------|
| ML-KEM-768   | NIST Level 3  | 1184 bytes | 2400 bytes | 1088 bytes | 32 bytes      |
| ML-KEM-1024  | NIST Level 5  | 1568 bytes | 3168 bytes | 1568 bytes | 32 bytes      |

**Files created:**
- `libsec/sha3.c` — SHA-3/SHAKE (Keccak-f[1600], prerequisite for ML-KEM/ML-DSA)
- `libsec/mlkem_ntt.c` — NTT arithmetic (q=3329, Barrett/Montgomery reduction)
- `libsec/mlkem_poly.c` — Polynomial operations (CBD sampling, compress/decompress)
- `libsec/mlkem.c` — ML-KEM-768/1024 keygen/encaps/decaps (CPAPKE + FO transform)

**Keyring API:** `mlkem768_keygen/encaps/decaps`, `mlkem1024_keygen/encaps/decaps` (raw byte arrays)

#### ML-DSA (FIPS 204) — Digital Signatures

| Parameter Set | Security Level | Public Key | Secret Key | Signature  |
|---------------|---------------|------------|------------|------------|
| ML-DSA-65     | NIST Level 3  | 1952 bytes | 4032 bytes | 3309 bytes |
| ML-DSA-87     | NIST Level 5  | 2592 bytes | 4896 bytes | 4627 bytes |

**Files created:**
- `libsec/mldsa_ntt.c` — NTT arithmetic (q=8380417)
- `libsec/mldsa_poly.c` — Polynomial operations (sampling, packing, hint/decompose)
- `libsec/mldsa.c` — ML-DSA-65/87 keygen/sign/verify (rejection sampling)
- `libkeyring/mldsaalg.c` — SigAlgVec registration (mldsa65, mldsa87)

**Keyring API:** Registered as SigAlgVec (`genSK("mldsa65", ...)`, standard sign/verify)

#### Hybrid TLS 1.3 Key Exchange

X25519MLKEM768 (IANA group 0x4588) hybrid key exchange per draft-ietf-tls-ecdhe-mlkem.

| Aspect | Classical | Hybrid |
|--------|-----------|--------|
| Client key share | 32 bytes (X25519) | 1216 bytes (ML-KEM pk + X25519) |
| Server response | 32 bytes | 1120 bytes (ML-KEM ct + X25519) |
| Shared secret | 32 bytes | 64 bytes (ML-KEM ss ‖ X25519 ss) |
| Fallback | — | X25519 if server doesn't support hybrid |

**Files modified:**
- `appl/lib/crypt/tls.b` — Hybrid key exchange in TLS 1.3 handshake
- `module/tls.m` — `X25519MLKEM768` constant

#### X.509 Certificate Support

ML-DSA OIDs added for certificate signing:
- `id-ML-DSA-65`: 2.16.840.1.101.3.4.3.18
- `id-ML-DSA-87`: 2.16.840.1.101.3.4.3.19

**Files modified:**
- `module/pkcs.m`, `appl/lib/crypt/pkcs.b` — ML-DSA OIDs
- `appl/cmd/auth/createsignerkey.b` — `mldsa65`/`mldsa87` algorithm options

#### Migration

```sh
# Generate ML-DSA-65 signer key
auth/createsignerkey -a mldsa65 signer_name

# Generate ML-DSA-87 signer key (higher security)
auth/createsignerkey -a mldsa87 signer_name
```

TLS hybrid key exchange is automatic — clients advertise X25519MLKEM768 first with X25519 fallback.

#### Testing

```sh
./emu/MacOSX/o.emu -r. /tests/sha3_test.dis
./emu/MacOSX/o.emu -r. /tests/mlkem_test.dis
./emu/MacOSX/o.emu -r. /tests/mldsa_test.dis
./emu/MacOSX/o.emu -r. /tests/tls_pq_test.dis
```

### 9. SLH-DSA (FIPS 205) — Stateless Hash-Based Signatures

Conservative backup for ML-DSA — no lattice assumptions, purely hash-based (WOTS+ + FORS + hypertree). Uses SHAKE-256 from `libsec/sha3.c`.

| Parameter Set | Security Level | Public Key | Secret Key | Signature |
|---------------|---------------|------------|------------|-----------|
| SLH-DSA-SHAKE-192s | NIST Level 3 | 48 bytes | 96 bytes | 16,224 bytes |
| SLH-DSA-SHAKE-256s | NIST Level 5 | 64 bytes | 128 bytes | 29,792 bytes |

**Architecture:** Five-layer construction:
- `slhdsa_hash.c` — ADRS address scheme, tweakable hash functions (F, H, T_l, PRF, H_msg)
- `slhdsa_wots.c` — WOTS+ one-time signatures (Winternitz w=16)
- `slhdsa_fors.c` — FORS few-time signatures (k=17/22 trees of height a=14)
- `slhdsa_tree.c` — XMSS tree and d-layer hypertree (sign/verify)
- `slhdsa.c` — Top-level keygen/sign/verify

**Files created:**
- `libsec/slhdsa.c` — SLH-DSA keygen/sign/verify
- `libsec/slhdsa_hash.c` — Tweakable hash functions, ADRS
- `libsec/slhdsa_wots.c` — WOTS+ one-time signatures
- `libsec/slhdsa_fors.c` — FORS few-time signatures
- `libsec/slhdsa_tree.c` — Merkle tree + hypertree
- `libkeyring/slhdsaalg.c` — SigAlgVec registration (slhdsa192s, slhdsa256s)

**Keyring API:** Registered as SigAlgVec (`genSK("slhdsa192s", ...)`, standard sign/verify). Uses slots 7-8 of the 8-slot `algs[]` array (all slots now filled).

**X.509 OIDs:**
- `id-SLH-DSA-SHAKE-192s`: 2.16.840.1.101.3.4.3.22
- `id-SLH-DSA-SHAKE-256s`: 2.16.840.1.101.3.4.3.26

**Files modified:**
- `include/libsec.h` — SLH-DSA declarations
- `libsec/mkfile` — Add 5 SLH-DSA source files
- `libkeyring/keys.h` — Bump Maxbuf to 49152, add init declarations
- `libkeyring/mkfile` — Add slhdsaalg.o
- `libinterp/keyring.c` — Register SLH-DSA algs + SHA-3 builtins
- `module/keyring.m` — SHA3-256/512 digest functions
- `module/pkcs.m`, `appl/lib/crypt/pkcs.b` — SLH-DSA OIDs
- `appl/cmd/auth/createsignerkey.b` — SLH-DSA algorithm options

#### SHA-3 Keyring Builtins

SHA3-256 and SHA3-512 exposed to Limbo as one-shot digest functions:

```limbo
SHA3_256dlen: con 32;
SHA3_512dlen: con 64;
sha3_256: fn(buf: array of byte, n: int, digest: array of byte): int;
sha3_512: fn(buf: array of byte, n: int, digest: array of byte): int;
```

#### Migration

```sh
# Generate SLH-DSA-SHAKE-192s signer key (Level 3)
auth/createsignerkey -a slhdsa192s signer_name

# Generate SLH-DSA-SHAKE-256s signer key (Level 5)
auth/createsignerkey -a slhdsa256s signer_name
```

#### Testing

```sh
./emu/Linux/o.emu -r. /tests/slhdsa_test.dis
./emu/Linux/o.emu -r. /tests/sha3_test.dis
```

## Security Properties (Updated)

After all changes, the complete SigAlgVec registry:

| Slot | Algorithm | Type | Security |
|------|-----------|------|----------|
| 1 | ed25519 | Classical | 128-bit |
| 2 | elgamal | Classical | ~112-bit (2048-bit) |
| 3 | rsa | Classical | Variable |
| 4 | dsa | Classical | Variable |
| 5 | mldsa65 | Post-Quantum (lattice) | NIST Level 3 |
| 6 | mldsa87 | Post-Quantum (lattice) | NIST Level 5 |
| 7 | slhdsa192s | Post-Quantum (hash) | NIST Level 3 |
| 8 | slhdsa256s | Post-Quantum (hash) | NIST Level 5 |

## Future Work

Optional improvements not yet implemented:

1. **OCSP stapling** - Online certificate status checking (alternative to CRL)
2. **CRL auto-fetch** - Fetch CRLs from CRL Distribution Point URLs in certificates
3. **TLS 1.3 for SSL3 path** - Migrate remaining SSL3 users to TLS 1.3 (already available in tls.b)
