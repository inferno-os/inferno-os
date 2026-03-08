/*
 * Secure memory clearing — guaranteed not to be optimized away.
 *
 * Uses platform-specific primitives where available,
 * falls back to a volatile function pointer trick.
 */
#include "os.h"
#include <libsec.h>

#if defined(__APPLE__) || defined(__linux__)
/* Both macOS and glibc/musl provide explicit_bzero */
void
secureZero(void *p, ulong n)
{
	explicit_bzero(p, n);
}
#else
/* Volatile function pointer prevents dead-store elimination */
static void
securezero_fallback(void *p, ulong n)
{
	volatile uchar *vp = (volatile uchar *)p;
	while(n--)
		*vp++ = 0;
}

static void (*volatile securezero_fn)(void *, ulong) = securezero_fallback;

void
secureZero(void *p, ulong n)
{
	securezero_fn(p, n);
}
#endif
