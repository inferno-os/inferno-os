#include "lib9.h"

ulong
_tas(ulong *la)
{
	ulong v;

	_asm {
		mov eax, la
		mov ebx, 1
		xchg	ebx, [eax]
		mov	v, ebx
	}
	return v;
}
