/*
 * Atomic test-and-set for Windows AMD64.
 *
 * MSVC x64 does not support inline assembly.
 * Use the InterlockedExchange intrinsic instead.
 */
#include <intrin.h>
#include "lib9.h"

int
_tas(int *la)
{
	return (int)_InterlockedExchange((volatile long *)la, 1);
}
