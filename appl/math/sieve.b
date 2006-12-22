implement Sieve;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
	arg: Arg;

M: con 16*1024*1024;
N: con 8*M;
T: con 2*1024*1024;

limit := array[5] of { M, N, 2*N, 3*N, 15*(N/4) };

Sieve: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	arg = load Arg Arg->PATH;

	np := 0;
	alg := 3;
	arg->init(argv);
	while((c := arg->opt()) != 0){
		case (c){
			'a' =>
				alg = int arg->arg();
		}
	}
	if(alg < 0 || alg > 4)
		alg = 3;
	lim := limit[alg];
	argv = arg->argv();
	if(argv != nil)
		lim = int hd argv;
	if(lim < 0 || lim > limit[alg])
		lim = limit[alg];
	if(lim < 6){
		if(lim > 2){
			sys->print("2\n");
			np++;
		}
		if(lim > 3){
			sys->print("3\n");
			np++;
		}
	}
	else{
		case (alg){
			0 => np = init0(lim);
			1 => np = init1(lim);
			2 => np = init2(lim);
			3 => np = init3(lim);
			4 => np = init4(lim);
		}
	}
	sys->print("%d primes < %d\n", np, lim);
}

init0(lim: int): int
{
	p := array[lim] of byte;
	for(i := 0; i < lim; i++)
		p[i] = byte 1;
	p[0] = p[1] = byte 0;
	np := 0;
	for(i = 0; i < lim; i++){
		if(p[i] == byte 1){
			np++;
			sys->print("%d\n", i);
			for(j := i+i; j < lim; j += i)
				p[j] = byte 0;
		}
	}
	return np;
}

init1(lim: int): int
{
	n := (lim+31)/32;
	p := array[n] of int;
	for(i := 0; i < n; i++)
		p[i] = int 16rffffffff;
	p[0] = int 16rfffffffc;
	np := 0;
	for(i = 0; i < lim; i++){
		if(p[i>>5] & (1<<(i&31))){
			np++;
			sys->print("%d\n", i);
			for(j := i+i; j < lim; j += i)
				p[j>>5] &= ~(1<<(j&31));
		}
	}
	return np;
}

init2(lim: int): int
{
	n := ((lim+1)/2+31)/32;
	p := array[n] of int;
	for(i := 0; i < n; i++)
		p[i] = int 16rffffffff;
	p[0] = int 16rfffffffe;
	np := 1;
	sys->print("%d\n", 2);
	for(i = 1; i < lim; i += 2){
		k := (i-1)>>1;
		if(p[k>>5] & (1<<(k&31))){
			np++;
			sys->print("%d\n", i);
			inc := i+i;
			for(j := i+i+i; j < lim; j += inc){
				k = (j-1)>>1;
				p[k>>5] &= ~(1<<(k&31));
			}
		}
	}
	return np;
}

init3(lim: int): int
{
	n := ((lim+2)/3+31)/32;
	p := array[n] of int;
	for(i := 0; i < n; i++)
		p[i] = int 16rffffffff;
	p[0] = int 16rfffffffe;
	np := 2;
	sys->print("%d\n", 2);
	sys->print("%d\n", 3);
	d := 2;
	for(i = 1; i < lim; i += d){
		k := (i-1)/3;
		if(p[k>>5] & (1<<(k&31))){
			np++;
			sys->print("%d\n", i);
			inc := 6*i;
			for(j := 5*i; j > 0 && j < lim; j += inc){
				k = (j-1)/3;
				p[k>>5] &= ~(1<<(k&31));
			}
			for(j = 7*i; j > 0 && j < lim; j += inc){
				k = (j-1)/3;
				p[k>>5] &= ~(1<<(k&31));
			}
		}
		d = 6-d;
	}
	return np;
}

init4(lim: int): int
{
	n := (4*((lim+14)/15)+31)/32;
	p := array[n] of int;
	for(i := 0; i < n; i++)
		p[i] = int 16rffffffff;
	p[0] = int 16rfffffffe;
	np := 3;
	sys->print("%d\n", 2);
	sys->print("%d\n", 3);
	sys->print("%d\n", 5);
	m := -1;
	d := array[8] of { 6, 4, 2, 4, 2, 4, 6, 2 };
	for(i = 1; i < lim; i += d[m]){
		k := (17*(i%30-1))/60+8*(i/30);
		if(p[k>>5] & (1<<(k&31))){
			np++;
			sys->print("%d\n", i);
			inc := 30*i;
			for(j := 7*i; j > 0 && j < lim; j += inc){
				k = (17*(j%30-1))/60+8*(j/30);
				p[k>>5] &= ~(1<<(k&31));
			}
			for(j = 11*i; j > 0 && j < lim; j += inc){
				k = (17*(j%30-1))/60+8*(j/30);
				p[k>>5] &= ~(1<<(k&31));
			}
			for(j = 13*i; j > 0 && j < lim; j += inc){
				k = (17*(j%30-1))/60+8*(j/30);
				p[k>>5] &= ~(1<<(k&31));
			}
			for(j = 17*i; j > 0 &&  j < lim; j += inc){
				k = (17*(j%30-1))/60+8*(j/30);
				p[k>>5] &= ~(1<<(k&31));
			}
			for(j = 19*i; j > 0 && j < lim; j += inc){
				k = (17*(j%30-1))/60+8*(j/30);
				p[k>>5] &= ~(1<<(k&31));
			}
			for(j = 23*i; j > 0 && j < lim; j += inc){
				k = (17*(j%30-1))/60+8*(j/30);
				p[k>>5] &= ~(1<<(k&31));
			}
			for(j = 29*i; j > 0 && j < lim; j += inc){
				k = (17*(j%30-1))/60+8*(j/30);
				p[k>>5] &= ~(1<<(k&31));
			}
			for(j = 31*i; j > 0 && j < lim; j += inc){
				k = (17*(j%30-1))/60+8*(j/30);
				p[k>>5] &= ~(1<<(k&31));
			}
		}
		m++;
		if(m == 8)
			m = 0;
	}
	return np;
}

init5(lim: int): int
{
	# you must be joking
	lim = 0;
	return 0;
}
