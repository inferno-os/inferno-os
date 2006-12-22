implement Ida;

#
# M Rabin, ``Efficient Dispersal of Information for Security,
#	Load Balancing, and Fault Tolerance'', JACM 36(2), April 1989, pp. 335-348
#	the scheme used below is that suggested at the top of page 340
#

include "sys.m";
	sys: Sys;

include "rand.m";
	rand: Rand;

include "ida.m";

invtab: array of int;

init()
{
	sys = load Sys Sys->PATH;
	rand = load Rand Rand->PATH;
	rand->init(sys->pctl(0, nil)^(sys->millisec()<<8));
	# the table is in a separate module so that
	# the copy in the module initialisation section is discarded
	# after unloading, preventing twice the space being used
	idatab := load Idatab Idatab->PATH;
	invtab = idatab->init();	# the big fella
	idatab = nil;
}

Field: con 65537;
Fmax: con Field-1;

div(a, b: int): int
{
	return mul(a, invtab[b]);
}

mul(a, b: int): int
{
	if(a == Fmax && b == Fmax)	# avoid overflow
		return 1;
	return int((big(a*b) & 16rFFFFFFFF) % big Field);
}

sub(a, b: int): int
{
	return ((a-b)+Field)%Field;
}

add(a, b: int): int
{
	return (a + b)%Field;
}

#
# return a fragment representing the encoded version of data
#
fragment(data: array of byte, m: int): ref Frag
{
	nb := len data;
	nw := (nb+1)/2;
	a := array[m] of {* => rand->rand(Fmax)+1};	# no zero elements
	f := array[(nw + m - 1)/m] of int;
	o := 0;
	i := 0;
	for(k := 0; k < len f; k++){
		c := 0;
		for(j := 0; j < m && i < nb; j++){
			b := int data[i++] << 8;
			if(i < nb)
				b |= int data[i++];
			c = add(c, mul(b, a[j]));
		}
		f[o++] = c;
	}
	return ref Frag(nb, m, a, f, nil);
}

#
# return the data encoded by the given set of fragments
#
reconstruct(frags: array of ref Frag): (array of byte, string)
{
	if(len frags < 1 || len frags < (m := frags[0].m))
		return (nil, "too few fragments");
	fraglen := len frags[0].enc;

	a := array[m] of array of int;
	for(j := 0; j < len a; j++){
		a[j] = frags[j].a;
		if(len a[j] != m)
			return (nil, "inconsistent encoding matrix");
		if(len frags[j].enc != fraglen)
			return (nil, "inconsistent fragments");
	}
	ainv := minvert(a);
	out := array[fraglen*2*m] of byte;
	o := 0;
	for(k := 0; k < fraglen; k++){
		for(i := 0; i < m; i++){
			row := ainv[i];
			b := 0;
			for(j = 0; j < m; j++)
				b = add(b, mul(frags[j].enc[k], row[j]));
			if((b>>16) != 0)
				return (nil, "corrupt output");
			out[o++] = byte (b>>8);
			out[o++] = byte b;
		}
	}
	if(frags[0].dlen < len out)
		out = out[0: frags[0].dlen];
	return (out, nil);
}

#
# Rabin's paper gives a way of building an encoding matrix that can then
# be inverted in O(m^2) operations, compared to O(m^3) for the following,
# but m is small enough it doesn't seem worth the added complication,
# and it's only done once per set
#
minvert(a: array of array of int): array of array of int
{
	m := len a;	# it's square
	out := array[m] of {* => array[m*2] of {* => 0}};
	for(r := 0; r < m; r++){
		out[r][0:] = a[r];
		out[r][m+r] = 1;	# identity matrix
	}
	for(r = 0; r < m; r++){
		x := out[r][r];	# by construction, cannot be zero, unless later corrupted
		for(c := 0; c < 2*m; c++)
			out[r][c] = div(out[r][c], x);
		for(r1 := 0; r1 < m; r1++)
			if(r1 != r){
				y := div(out[r1][r], out[r][r]);
				for(c = 0; c < 2*m; c++)
					out[r1][c] = sub(out[r1][c], mul(y, out[r][c]));
			}
	}
	for(r = 0; r < m; r++)
		out[r] = out[r][m:];
	return out;
}

Val: adt {
	v:	int;
	n:	int;
};

addval(vl: list of ref Val, v: int): list of ref Val
{
	for(l := vl; l != nil; l = tl l)
		if((hd l).v == v){
			(hd l).n++;
			return vl;
		}
	return ref Val(v, 1) :: vl;
}

mostly(vl: list of ref Val): ref Val
{
	if(len vl == 1)
		return hd vl;
	v: ref Val;
	for(; vl != nil; vl = tl vl)
		if(v == nil || (hd vl).n > v.n)
			v = hd vl;
	return v;
}

#
# return a consistent set of Frags: all parameters agree with the majority,
# and obviously bad fragments have been discarded
#
# in the absence of error, they  should all have the same value, so lists are fine;
# could separately return the discarded ones, out of interest
#
consistent(frags: array of ref Frag): array of ref Frag
{
	t := array[len frags] of ref Frag;
	t[0:] = frags;
	frags = t;
	ds: list of ref Val;	# data size
	ms: list of ref Val;
	fls: list of ref Val;
	for(i := 0; i < len frags; i++){
		f := frags[i];
		if(f != nil){
			ds = addval(ds, f.dlen);
			ms = addval(ms, f.m);
			fls = addval(fls, len f.enc);
		}
	}
	dv := mostly(ds);
	mv := mostly(ms);
	flv := mostly(fls);
	if(mv == nil || flv == nil || dv == nil)
		return nil;
	for(i = 0; i < len frags; i++){
		f := frags[i];
		if(f == nil || f.m != mv.v || f.m != len f.a || len f.enc != flv.v || f.dlen != dv.v || badfrag(f)){	# inconsistent: drop it
			if(i+1 < len frags)
				frags[i:] = frags[i+1:];
			frags = frags[0:len frags-1];
		}
	}
	if(len frags == 0)
		return nil;
	return frags;
}

badfrag(f: ref Frag): int
{
	for(i := 0; i < len f.a; i++){
		v := f.a[i];
		if(v <= 0 || v >= Field)
			return 1;
	}
	for(i = 0; i < len f.a; i++){
		v := f.enc[i];
		if(v == 0 || v >= Field)
			return 1;
	}
	return 0;
}
