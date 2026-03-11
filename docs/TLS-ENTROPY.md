# TLS Entropy Source Selection

## Background

Inferno's cons driver (`#c`) serves two entropy devices:

| Device | Implementation | Throughput | Use case |
|--------|---------------|------------|----------|
| `#c/random` | Timing jitter between two kprocs | ~80ms/byte | Bare-metal Inferno |
| `#c/notquiterandom` | `prng()` in `libsec/prng.c` | nanoseconds/byte | emu on macOS/Linux |

## How `#c/random` works

Two kernel processes run concurrently: `genrandom` spins counting a free-running
counter, and `randomclock` wakes every 20ms and samples that counter.  The timing
difference between the two processes provides genuine hardware entropy — the
scheduler jitter on real hardware is unpredictable.

One byte is written to the ring buffer every 4 clock ticks (80ms).  Generating
64 bytes of key material (two 32-byte values for a TLS handshake) takes ~5 seconds.

On bare-metal Inferno this is appropriate: there is no OS underneath providing
a better source, and the jitter is real.

## How `#c/notquiterandom` works

`#c/notquiterandom` calls `prng()` in `libsec/prng.c`, which is platform-specific:

- **macOS**: `arc4random_buf(p, n)` — ChaCha20 CSPRNG seeded from the hardware
  entropy pool via `SecRandomCopyBytes` / RDRAND.  Despite the "arc4" name,
  Apple replaced the RC4 internals with ChaCha20 circa 2013.
- **Linux**: `getrandom(p, n, 0)` — the kernel CSPRNG, also ChaCha20-based,
  seeded from hardware entropy (`/dev/hwrng`, RDRAND, boot-time jitter, etc.).
- **Other POSIX**: falls back to `open("/dev/urandom")`.

These sources pass NIST SP 800-90A/B statistical tests and are used by the host
OS for all its own cryptographic operations.

## Why `tls.b` prefers `#c/notquiterandom`

The name "notquiterandom" is a historical Inferno convention dating from when it
was a weak LCG.  The name has not caught up with the implementation.  In this
codebase, when running under emu, it is the **stronger** source:

- Draws from a larger entropy pool than clock jitter
- Not predictable on virtualised or containerised hosts where scheduling is
  controlled by the hypervisor (timing-based entropy is weaker on VMs)
- Five orders of magnitude faster: nanoseconds vs 80ms/byte

`tls.b` opens entropy sources in priority order with fallback:

```limbo
randomfd = sys->open("#c/notquiterandom", Sys->OREAD);  # fast OS CSPRNG
if(randomfd == nil)
    randomfd = sys->open("/dev/urandom", Sys->OREAD);   # POSIX fallback
if(randomfd == nil)
    randomfd = sys->open("#c/random", Sys->OREAD);      # bare-metal fallback
```

The fd is opened **once** in `init()` and reused across all TLS connections.
Opening `#c/random` per-call was the original code; each open added to the
startup latency without improving entropy quality.

## Bare-metal Inferno

On bare-metal Inferno (no host OS), `prng()` is not available and
`#c/notquiterandom` may fall back to a weaker implementation.  The fallback
chain in `tls.b` ensures `#c/random` is used in that case.

If porting `tls.b` to run on bare-metal Inferno, verify that
`#c/notquiterandom` provides adequate entropy for the target hardware, or
reverse the priority order so `#c/random` is tried first.

## Performance impact

Measured on macOS ARM64 (Apple M-series) running Inferno emu:

| Configuration | Per-connection TLS | Wikipedia load |
|---------------|-------------------|----------------|
| `#c/random` (original) | ~9,000ms | ~46,000ms |
| `#c/notquiterandom` (current) | ~100–2,400ms | ~3,500ms |

The first connection is slower (~2.4s) because it includes RSA certificate
chain verification in pure Limbo.  Subsequent connections to the same server
reuse TLS 1.3 session tickets and take only network RTT (~100ms).

## References

- `emu/port/random.c` — `#c/random` implementation and design comments
- `libsec/prng.c` — `prng()` platform implementations
- `appl/lib/crypt/tls.b` — entropy selection in `init()` and `randombuf()`
