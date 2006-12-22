implement Remap;

include "sys.m";
include "mpegio.m";

Mpegi, YCbCr: import Mpegio;

CLOFF: con 255;

width, height, w4: int;
out: array of byte;
elum: array of int;
clamp4 := array[CLOFF + 256 + CLOFF] of int;

init(m: ref Mpegi)
{
	width = m.width;
	height = m.height;
	w4 = width >> 2;
	out = array[w4 * height] of byte;
	elum = array[width + 1] of int;
	for (i := 0; i < CLOFF; i++)
		clamp4[i] = 0;
	for (i = 0; i < 256; i++)
		clamp4[i + CLOFF] = i >> 6;
	for (i = CLOFF + 256; i < CLOFF + 256 + CLOFF; i++)
		clamp4[i] = 255 >> 6;
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
		for (k := 0; k < w4; k++) {
			y := (256 - int Y[n++]) + elum[ex];
			l := clamp4[y + CLOFF] << 6;
			b := l;
			y -= l;
			t := (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp4[y + CLOFF];
			b |= l << 4;
			y -= l << 6;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp4[y + CLOFF];
			b |= l << 2;
			y -= l << 6;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp4[y + CLOFF];
			out[m++] = byte (b | l);
			y -= l << 6;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
		}
	}
	return out;
}
