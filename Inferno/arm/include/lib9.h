#include <u.h>
#include <kern.h>

/*
 *	Extensions for Inferno to basic libc.h
 */

#define __LITTLE_ENDIAN /* math/dtoa.c; longs in ARM doubles are big-endian */
