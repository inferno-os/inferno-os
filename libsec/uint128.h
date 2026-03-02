/*
 * uint128.h - Cross-platform 128-bit unsigned integer support.
 *
 * GCC/Clang: uses native __int128.
 * MSVC: emulates with struct + _umul128() intrinsic.
 *
 * Provides: u128 type, MUL128, ADD128, SUB128, LO128, HI128, SHR128_64
 */

#ifndef _UINT128_H_
#define _UINT128_H_

#ifdef _MSC_VER

#include <intrin.h>

typedef struct { u64int lo, hi; } u128;

static __forceinline u128
U128(u64int lo, u64int hi)
{
	u128 r;
	r.lo = lo;
	r.hi = hi;
	return r;
}

static __forceinline u128
U128_FROM64(u64int v)
{
	u128 r;
	r.lo = v;
	r.hi = 0;
	return r;
}

static __forceinline u128
MUL128(u64int a, u64int b)
{
	u128 r;
	r.lo = _umul128(a, b, &r.hi);
	return r;
}

static __forceinline u128
ADD128(u128 a, u128 b)
{
	u128 r;
	r.lo = a.lo + b.lo;
	r.hi = a.hi + b.hi + (r.lo < a.lo);
	return r;
}

static __forceinline u128
ADD128_64(u128 a, u64int b)
{
	u128 r;
	r.lo = a.lo + b;
	r.hi = a.hi + (r.lo < a.lo);
	return r;
}

static __forceinline u128
SUB128(u128 a, u128 b)
{
	u128 r;
	r.hi = a.hi - b.hi - (a.lo < b.lo);
	r.lo = a.lo - b.lo;
	return r;
}

static __forceinline u128
SUB128_64(u128 a, u64int b)
{
	u128 r;
	r.hi = a.hi - (a.lo < b);
	r.lo = a.lo - b;
	return r;
}

#define LO128(v)      ((v).lo)
#define HI128(v)      ((v).hi)
#define SHR128_64(v)  ((v).hi)
#define IS_ZERO128(v) ((v).lo == 0 && (v).hi == 0)

#else /* GCC/Clang: native __int128 */

typedef unsigned __int128 u128;

#define U128(lo, hi)      ((u128)(lo) | ((u128)(hi) << 64))
#define U128_FROM64(v)    ((u128)(u64int)(v))
#define MUL128(a, b)      ((u128)(a) * (b))
#define ADD128(a, b)      ((a) + (b))
#define ADD128_64(a, b)   ((a) + (u64int)(b))
#define SUB128(a, b)      ((a) - (b))
#define SUB128_64(a, b)   ((a) - (u64int)(b))
#define LO128(v)          ((u64int)(v))
#define HI128(v)          ((u64int)((v) >> 64))
#define SHR128_64(v)      ((u64int)((v) >> 64))
#define IS_ZERO128(v)     ((v) == 0)

#endif

#endif /* _UINT128_H_ */
