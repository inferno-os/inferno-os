implement Remap;

include "sys.m";
include "mpegio.m";

Mpegi, YCbCr: import Mpegio;

CLOFF: con 255;

width, height, w2, h2: int;
out: array of byte;
ered, egrn, eblu: array of int;
b0r1, b1, r0: array of int;
clamp := array[CLOFF + 256 + CLOFF] of int;
clamp16 := array[CLOFF + 256 + CLOFF] of int;

init(m: ref Mpegi)
{
	width = m.width;
	height = m.height;
	w2 = width >> 1;
	h2 = height >> 1;
	out = array[width * height] of byte;
	b0r1 = array[w2] of int;
	b1 = array[w2] of int;
	r0 = array[w2] of int;
	ered = array[width + 1] of int;
	egrn = array[width + 1] of int;
	eblu = array[width + 1] of int;
	for (i := 0; i < CLOFF; i++) {
		clamp[i] = 0;
		clamp16[i] = 0;
	}
	for (i = 0; i < 256; i++) {
		clamp[i + CLOFF] = i;
		clamp16[i + CLOFF] = i >> 4;
	}
	for (i = CLOFF + 256; i < CLOFF + 256 + CLOFF; i++) {
		clamp[i] = 255;
		clamp16[i] = 255 >> 4;
	}
}

include "closest.m";
include "rgbvmap.m";

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
	for (e := 0; e <= width; e++)
		ered[e] = 0;
	egrn[0:] = ered[0:];
	eblu[0:] = ered[0:];
	m := 0;
	n := 0;
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
			ex := 0;
			er := 0;
			eg := 0;
			eb := 0;
			for (k := 0; k < w2; k++) {
				l := 2;
				do {
					y := int Y[n] << B;
					r := clamp[((y + r0[k]) >> B) + CLOFF] + ered[ex];
					g := clamp[((y + b0r1[k]) >> B) + CLOFF] + egrn[ex];
					b := clamp[((y + b1[k]) >> B) + CLOFF] + eblu[ex];
					rc := clamp16[r + CLOFF];
					gc := clamp16[g + CLOFF];
					bc := clamp16[b + CLOFF];
					col := int closest[bc + 16 * (gc + 16 * rc)];
					out[n++] = byte col;

					col *= 3;
					r -= int rgbvmap[col + 0];
					t := (3 * r) >> 4;
					ered[ex] = t + er;
					ered[ex + 1] += t;
					er = r - 3 * t;

					g -= int rgbvmap[col + 1];
					t = (3 * g) >> 4;
					egrn[ex] = t + eg;
					egrn[ex + 1] += t;
					eg = g - 3 * t;

					b -= int rgbvmap[col + 2];
					t = (3 * b) >> 4;
					eblu[ex] = t + eb;
					eblu[ex + 1] += t;
					eb = b - 3 * t;
					ex++;
				} while (--l > 0);
			}
		} while (--j > 0);
	}
	return out;
}
