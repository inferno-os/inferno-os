implement IDCT;

include "sys.m";
include "math.m";
include "mpegio.m";

sys: Sys;
math: Math;

#
#	Reference IDCT.  Full expanded 2-d IDCT.
#

coeff: array of array of real;

init()
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	if (math == nil) {
		sys->fprint(sys->fildes(2), "could not load %s: %r\n", Math->PATH);
		exit;
	}
	init_idct();
}

init_idct()
{
	coeff = array[8] of array of real;
	for (f := 0; f < 8; f++) {
		coeff[f] = array[8] of real;
		s := 0.5;
		if (f == 0)
			s = math->sqrt(0.125);
		a := real f * (Math->Pi / 8.0);
		for (t := 0; t < 8; t++) 
			coeff[f][t] = s * math->cos(a * (real t + 0.5));
	}
}

idct(block: array of int)
{
	tmp := array[64] of real;
	for (i := 0; i < 8; i++)
		for (j := 0; j < 8; j++) {
			p := 0.0;
			for (k := 0; k < 8; k++)
				p += coeff[k][j] * real block[8 * i + k];
			tmp[8 * i + j] = p;
		}
	for (j = 0; j < 8; j++)
		for (i = 0; i < 8; i++) {
			p := 0.0;
			for (k := 0; k < 8; k++)
				p += coeff[k][i] * tmp[8 * k + j];
			block[8 * i + j] = int p;
		}
}
