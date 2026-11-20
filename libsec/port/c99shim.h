/*
 * The C99 names the imported sources (Monocypher, the pq-crystals
 * reference code) use, for compilers without <stdint.h>: the Plan 9
 * compilers of the native kernels. Hosted builds take the real headers.
 * (Those compilers have no #if either, only #ifdef.)
 * Include this instead of <stddef.h>, <stdint.h> and <string.h>.
 * A file that has already included lib9.h (or os.h) defines
 * C99SHIM_HAVE_LIB9 first.
 */
#ifdef __GNUC__
#define C99HOSTED
#endif
#ifdef __STDC_VERSION__
#define C99HOSTED
#endif
#ifdef _MSC_VER
#define C99HOSTED
#endif
#ifdef C99HOSTED
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#else
#ifndef C99SHIM_HAVE_LIB9
#include <lib9.h>
#endif
typedef signed char	int8_t;
typedef unsigned char	uint8_t;
typedef short		int16_t;
typedef unsigned short	uint16_t;
typedef int		int32_t;
typedef unsigned int	uint32_t;
typedef long long	int64_t;
typedef unsigned long long	uint64_t;
#ifndef NULL
#define NULL	((void*)0)
#endif
#endif

/*
 * Work areas too large for a kernel stack (8 KiB in the native kernels)
 * come from the heap. secwork returns n zeroed bytes and does not return
 * without them; secworkfree wipes them and frees them. In modern.c.
 */
extern void*	secwork(unsigned long);
extern void	secworkfree(void*, unsigned long);
