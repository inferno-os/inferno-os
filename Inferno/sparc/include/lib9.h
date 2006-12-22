#include <u.h>
#include <kern.h>


/*
 *	Extensions for Inferno to basic libc.h
 */

#undef __LITTLE_ENDIAN /* math/dtoa.c; longs in SPARC doubles are big-endian */
