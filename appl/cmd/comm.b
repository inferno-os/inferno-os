implement Comm;

# Copyright © 2002 Lucent Technologies Inc.
# Subject to the Lucent Public Licence 1.02
# Limbo translation by Vita Nuova 2004; bug fixed.

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";

Comm: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

One, Two, Three: con 1<<iota;
cols := One|Two|Three;
ldr := array[3] of {"", "\t", "\t\t"};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("comm [-123] file1 file2");
	while((c := arg->opt()) != 0){
		case c {
		'1' to '3' =>
			cols &= ~(1 << (c-'1'));
		* =>
			arg->usage();
		}
	}
	args = arg->argv();
	if(len args != 2)
		arg->usage();
	arg = nil;

	if((cols & One) == 0){
		ldr[1] = "";
		ldr[2] = ldr[2][1:];
	}
	if((cols & Two) == 0)
		ldr[2] = ldr[2][1:];

	ib1 := openfil(hd args);
	ib2 := openfil(hd tl args);
	if((lb1 := ib1.gets('\n')) == nil){
		if((lb2 := ib2.gets('\n')) == nil)
			exit;
		copy(ib2, lb2, 2);
	}
	if((lb2 := ib2.gets('\n')) == nil)
		copy(ib1, lb1, 1);
	for(;;)
		case compare(lb1, lb2) {
		0 =>
			wr(lb1, 3);
			if((lb1 = ib1.gets('\n')) == nil){
				if((lb2 = ib2.gets('\n')) == nil)
					exit;
				copy(ib2, lb2, 2);
			}
			if((lb2 = ib2.gets('\n')) == nil)
				copy(ib1, lb1, 1);
		1 =>
			wr(lb1, 1);
			if((lb1 = ib1.gets('\n')) == nil)
				copy(ib2, lb2, 2);
		2 =>
			wr(lb2, 2);
			if((lb2 = ib2.gets('\n')) == nil)
				copy(ib1, lb1, 1);
		}
}

wr(str: string, n: int)
{
	if(cols & (1<<(n-1)))
		sys->print("%s%s", ldr[n-1], str);
}

copy(ibuf: ref Iobuf, lbuf: string, n: int)
{
	do
		wr(lbuf, n);
	while((lbuf = ibuf.gets('\n')) != nil);
	exit;
}

compare(a: string, b: string): int
{
	for(i := 0; i < len a; i++){
		if(i >= len b || a[i] < b[i])
			return 1;
		if(a[i] != b[i])
			return 2;
	}
	if(i == len b)
		return 0;
	return 2;
}

openfil(s: string): ref Iobuf
{
	if(s == "-")
		b := bufio->fopen(sys->fildes(0), Bufio->OREAD);
	else
		b = bufio->open(s, Bufio->OREAD);
	if(b != nil)
		return b;
	sys->fprint(sys->fildes(2), "comm: cannot open %s: %r\n", s);
	raise "fail:open";
}

