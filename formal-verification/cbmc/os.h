/*
 * Stub os.h for CBMC verification of libsec crypto code.
 *
 * Provides the Inferno type definitions needed by mlkem_ntt.c
 * and mlkem_poly.c without pulling in the full Inferno headers.
 */
#ifndef CBMC_OS_H
#define CBMC_OS_H

#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;
typedef long long vlong;
typedef unsigned long long uvlong;
typedef int16_t int16;
typedef uint16_t u16int;
typedef int32_t int32;
typedef uint32_t u32int;
typedef int64_t int64;
typedef uint64_t u64int;

#define nil  ((void*)0)
#define USED(x)  ((void)(x))

#endif /* CBMC_OS_H */
