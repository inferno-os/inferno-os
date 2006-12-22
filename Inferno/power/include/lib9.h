#include <u.h>
#include <kern.h>

#undef __LITTLE_ENDIAN /* math/dtoa.c; longs in PowerPC doubles are big-endian */
