implement Remap;

include "sys.m";
include "mpegio.m";

Mpegi, YCbCr: import Mpegio;

CLOFF: con 255;

width, height, w2: int;
out: array of byte;
elum: array of int;
clamp16 := array[CLOFF + 256 + CLOFF] of int;

init(m: ref Mpegi)
{
	width = m.width;
	height = m.height;
	w2 = width >> 1;
	out = array[w2 * height] of byte;
	elum = array[width + 1] of int;
	for (i := 0; i < CLOFF; i++)
		clamp16[i] = 0;
	for (i = 0; i < 256; i++)
		clamp16[i + CLOFF] = i >> 4;
	for (i = CLOFF + 256; i < CLOFF + 256 + CLOFF; i++)
		clamp16[i] = 255 >> 4;
}

remap(p: ref Mpegio->YCbCr): array of byte
{
	Y := p.Y;
	for (e := 0; e <= width; e++)
		elum[e] = 0;
	m := 0;
	n := 0;
	for (i := 0; i < height; i++) {
		el := 0;
		ex := 0;
		for (k := 0; k < w2; k++) {
			y := (256 - int Y[n++]) + elum[ex];
			l := clamp16[y + CLOFF] << 4;
			b := l;
			y -= l;
			t := (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp16[y + CLOFF];
			out[m++] = byte (b | l);
			y -= l << 4;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
		}
	}
	return out;
}
