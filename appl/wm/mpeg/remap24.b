implement Remap;

include "sys.m";
include "mpegio.m";

Mpegi, YCbCr: import Mpegio;

CLOFF: con 255;

width, height, w2, h2: int;
out: array of byte;
b0r1, b1, r0: array of int;
clamp := array[CLOFF + 256 + CLOFF] of byte;

init(m: ref Mpegi)
{
	width = m.width;
	height = m.height;
	w2 = width >> 1;
	h2 = height >> 1;
	out = array[3 * width * height] of byte;
	b0r1 = array[w2] of int;
	b1 = array[w2] of int;
	r0 = array[w2] of int;
	for (i := 0; i < CLOFF; i++)
		clamp[i] = byte 0;
	for (i = 0; i < 256; i++)
		clamp[i + CLOFF] = byte i;
	for (i = CLOFF + 256; i < CLOFF + 256 + CLOFF; i++)
		clamp[i] = byte 255;
}

#	rgb(y, cb, cr: int): (int, int, int)
#	{
#		Y := real y;
#		Cb := real (cb - 128);
#		Cr := real (cr - 128);
#		r := int (Y+1.402*Cr);
#		g := int (Y-0.34414*Cb-0.71414*Cr);
#		b := int (Y+1.772*Cb);
#		return (r, g, b);
#	}

B: con 16;
M: con (1 << B);
B0: con int (-0.34414 * real M);
B1: con int (1.772 * real M);
R0: con int (1.402 * real M);
R1: con int (-0.71414 * real M);

remap(p: ref Mpegio->YCbCr): array of byte
{
	Y := p.Y;
	Cb := p.Cb;
	Cr := p.Cr;
	m := 0;
	n := 0;
	x := 0;
	for (i := 0; i < h2; i++) {
		for (j := 0; j < w2; j++) {
			cb := int Cb[m] - 128;
			cr := int Cr[m] - 128;
			b0r1[j] = B0 * cb + R1 * cr;
			b1[j] = B1 * cb;
			r0[j] = R0 * cr;
			m++;
		}
		j = 2;
		do {
			for (k := 0; k < w2; k++) {
				l := 2;
				do {
					y := int Y[n++] << B;
					out[x++] = clamp[((y + r0[k]) >> B) + CLOFF];
					out[x++] = clamp[((y + b0r1[k]) >> B) + CLOFF];
					out[x++] = clamp[((y + b1[k]) >> B) + CLOFF];
				} while (--l > 0);
			}
		} while (--j > 0);
	}
	return out;
}
