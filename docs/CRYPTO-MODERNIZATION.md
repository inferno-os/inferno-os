# Cryptographic Modernization Summary

**Status:** Complete (Phase 1-5 + ElGamal fix)

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

- [CRYPTO-DEBUGGING-GUIDE.md](CRYPTO-DEBUGGING-GUIDE.md) - Debugging methodology
- [ELGAMAL-PERFORMANCE.md](ELGAMAL-PERFORMANCE.md) - Detailed performance analysis

## Commits

- `850e906a` - feat(crypto): Add Ed25519 signatures and modernize cryptography
- `172d7f7f` - Add RFC 3526 pre-computed DH params for fast ElGamal 2048-bit keygen

## Future Work

Optional improvements not yet implemented:

1. **OCSP stapling** - Online certificate status checking (alternative to CRL)
2. **CRL auto-fetch** - Fetch CRLs from CRL Distribution Point URLs in certificates
3. **Post-quantum cryptography** - ML-KEM (Kyber) for key encapsulation, ML-DSA (Dilithium) for signatures
4. **TLS 1.3 for SSL3 path** - Migrate remaining SSL3 users to TLS 1.3 (already available in tls.b)
