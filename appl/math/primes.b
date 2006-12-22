implement Primes;

#
# primes starting [ending]
#
# Subject to the Lucent Public License 1.02
#

include "draw.m";

Primes: module
{
	init: fn(nil: ref Draw->Context, argl: list of string);
};

include "sys.m";
	sys: Sys;
include "math.m";
	maths: Math;

bigx: con 9.007199254740992e15;
pt := array[] of {
	2,
	3,
	5,
	7,
	11,
	13,
	17,
	19,
	23,
	29,
	31,
	37,
	41,
	43,
	47,
	53,
	59,
	61,
	67,
	71,
	73,
	79,
	83,
	89,
	97,
	101,
	103,
	107,
	109,
	113,
	127,
	131,
	137,
	139,
	149,
	151,
	157,
	163,
	167,
	173,
	179,
	181,
	191,
	193,
	197,
	199,
	211,
	223,
	227,
	229,
};
wheel := array[] of {
	10.0,
	2.0,
	4.0,
	2.0,
	4.0,
	6.0,
	2.0,
	6.0,
	4.0,
	2.0,
	4.0,
	6.0,
	6.0,
	2.0,
	6.0,
	4.0,
	2.0,
	6.0,
	4.0,
	6.0,
	8.0,
	4.0,
	2.0,
	4.0,
	2.0,
	4.0,
	8.0,
	6.0,
	4.0,
	6.0,
	2.0,
	4.0,
	6.0,
	2.0,
	6.0,
	6.0,
	4.0,
	2.0,
	4.0,
	6.0,
	2.0,
	6.0,
	4.0,
	2.0,
	4.0,
	2.0,
	10.0,
	2.0,
};
BITS: con 8;
TABLEN: con 1000;
table := array[TABLEN] of byte;
bittab := array[8] of {
	byte 1,
	byte 2,
	byte 4,
	byte 8,
	byte 16,
	byte 32,
	byte 64,
	byte 128,
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	maths = load Math Math->PATH;

	if(len args <= 1){
		sys->fprint(sys->fildes(2), "usage: primes starting [ending]\n");
		raise "fail:usage";
	}
	args = tl args;
	nn := real hd args;
	limit := bigx;
	if(tl args != nil){
		limit = real hd tl args;
		if(limit < nn)
			exit;
		if(limit > bigx)
			ouch();
	}
	if(nn < 0.0 || nn > bigx)
		ouch();
	if(nn == 0.0)
		nn = 1.0;
	if(nn < 230.0){
		for(i := 0; i < len pt; i++){
			r := real pt[i];
			if(r < nn)
				continue;
			if(r > limit)
				exit;
			sys->print("%d\n", pt[i]);
			if(limit >= bigx)
				exit;
		}
		nn = 230.0;
	}
	(t, nil) := maths->modf(nn/2.0);
	nn = 2.0*real t+1.0;
	for(;;){
		# 
		# clear the sieve table.
		#  
		for(i := 0; i < len table; i++)
			table[i] = byte 0;
		# 
		# run the sieve
		#  
		v := maths->sqrt(nn+real (TABLEN*BITS));
		mark(nn, 3);
		mark(nn, 5);
		mark(nn, 7);
		i = 0;
		for(k := 11.0; k <= v; k += wheel[i]){
			mark(nn, int k);
			i++;
			if(i >= len wheel)
				i = 0;
		}
		# 
		# now get the primes from the table and print them
		#  
		for(i = 0; i < TABLEN*BITS; i += 2){
			if(int table[i>>3]&int bittab[i&8r7])
				continue;
			temp := nn+real i;
			if(temp > limit)
				exit;
			sys->print("%d\n", int temp);
			if(limit >= bigx)
				exit;
		}
		nn += real (TABLEN*BITS);
	}
}

mark(nn: real, k: int)
{
	(it1, nil) := maths->modf(nn/real k);
	j := int (real k*real it1-nn);
	if(j < 0)
		j += k;
	for(; j < len table*BITS; j += k)
		table[j>>3] |= bittab[j&8r7];
}

ouch()
{
	sys->fprint(sys->fildes(2), "primes: limits exceeded\n");
	raise "fail:ouch";
}

