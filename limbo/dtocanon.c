#include "limbo.h"

/*
 * Convert between host double and canonical (big-endian) representation
 * as two 32-bit words.
 *
 * The original code used a union of double with unsigned long[2],
 * which assumed sizeof(unsigned long) == 4.  On LP64 platforms
 * (ARM64 macOS/Linux, AMD64), unsigned long is 8 bytes, making
 * the union 16 bytes — twice the size of a double — and causing
 * all real constants to be silently corrupted to ~0.
 *
 * Fix: use u32int (uint32_t) so the union is always 8 bytes,
 * correctly overlaying the double.
 */

void
dtocanon(double f, ulong v[])
{
	union { double d; u32int ul[2]; } a;

	a.d = 1.;
	if(a.ul[0]){
		a.d = f;
		v[0] = a.ul[0];
		v[1] = a.ul[1];
	}else{
		a.d = f;
		v[0] = a.ul[1];
		v[1] = a.ul[0];
	}
}

double
canontod(ulong v[2])
{
	union { double d; u32int ul[2]; } a;

	a.d = 1.;
	if(a.ul[0]) {
		a.ul[0] = (u32int)v[0];
		a.ul[1] = (u32int)v[1];
	}
	else {
		a.ul[1] = (u32int)v[0];
		a.ul[0] = (u32int)v[1];
	}
	return a.d;
}
