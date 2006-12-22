implement Remap;

include "sys.m";
include "mpegio.m";

Mpegi, YCbCr: import Mpegio;

CLOFF: con 511;

width, height, w8: int;
out: array of byte;
elum: array of int;
clamp2 := array[CLOFF + 256 + CLOFF] of int;

init(m: ref Mpegi)
{
	width = m.width;
	height = m.height;
	w8 = width >> 3;
	out = array[w8 * height] of byte;
	elum = array[width + 1] of int;
	for (i := 0; i < CLOFF; i++)
		clamp2[i] = 0;
	for (i = 0; i < 256; i++)
		clamp2[i + CLOFF] = i >> 7;
	for (i = CLOFF + 256; i < CLOFF + 256 + CLOFF; i++)
		clamp2[i] = 255 >> 7;
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
		for (k := 0; k < w8; k++) {
			y := (256 - int Y[n++]) + elum[ex];
			l := clamp2[y + CLOFF] << 7;
			b := l;
			y -= l;
			t := (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp2[y + CLOFF];
			b |= l << 6;
			y -= l << 7;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp2[y + CLOFF];
			b |= l << 5;
			y -= l << 7;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp2[y + CLOFF];
			b |= l << 4;
			y -= l << 7;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp2[y + CLOFF];
			b |= l << 3;
			y -= l << 7;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp2[y + CLOFF];
			b |= l << 2;
			y -= l << 7;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp2[y + CLOFF];
			b |= l << 1;
			y -= l << 7;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
			y = (256 - int Y[n++]) + elum[ex];
			l = clamp2[y + CLOFF];
			out[m++] = byte (b | l);
			y -= l << 7;
			t = (3 * y) >> 4;
			elum[ex] = t + el;
			elum[ex + 1] += t;
			el = y - 3 * t;
			ex++;
		}
	}
	return out;
}
