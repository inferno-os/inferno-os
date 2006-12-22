implement Freq;

#
#	Copyright © 2002 Lucent Technologies Inc.
# 	transliteration of the Plan 9 command; subject to the Lucent Public License 1.02
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";

Freq: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

count := array[1<<16] of big;
flag := 0;

Fdec, Fhex, Foct, Fchar, Frune: con 1<<iota;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;

	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		* =>
			sys->fprint(sys->fildes(2), "freq: unknown option %c\n", c);
			raise "fail:usage";
		'd' =>
			flag |= Fdec;
		'x' =>
			flag |= Fhex;
		'o' =>
			flag |= Foct;
		'c' =>
			flag |= Fchar;
		'r' =>
			flag |= Frune;
		}
	args = arg->argv();
	arg = nil;

	bout := bufio->fopen(sys->fildes(1), Sys->OWRITE);
	if((flag&(Fdec|Fhex|Foct|Fchar)) == 0)
		flag |= Fdec|Fhex|Foct|Fchar;
	if(args == nil){
		freq(sys->fildes(0), "-", bout);
		exit;
	}
	for(; args != nil; args = tl args){
		f := sys->open(hd args, Sys->OREAD);
		if(f == nil){
			sys->fprint(sys->fildes(2), "cannot open %s\n", hd args);
			continue;
		}
		freq(f, hd args, bout);
		f = nil;
	}
}

freq(f: ref Sys->FD, s: string, bout: ref Iobuf)
{
	c: int;

	bin := bufio->fopen(f, Sys->OREAD);
	if(flag&Frune)
		for(;;){
			c = bin.getc();
			if(c < 0)
				break;
			count[c]++;
		}
	else
		for(;;){
			c = bin.getb();
			if(c < 0)
				break;
			count[c]++;
		}
	if(c != Bufio->EOF)
		sys->fprint(sys->fildes(2), "freq: read error on %s: %r\n", s);
	for(i := 0; i < (len count)/4; i++){
		if(count[i] == big 0)
			continue;
		if(flag&Fdec)
			bout.puts(sys->sprint("%3d ", i));
		if(flag&Foct)
			bout.puts(sys->sprint("%.3o ", i));
		if(flag&Fhex)
			bout.puts(sys->sprint("%.2x ", i));
		if(flag&Fchar)
			if(i <= 16r20 || i >= 16r7f && i < 16ra0 || i > 16rff && !(flag&Frune))
				bout.puts("- ");
			else
				bout.puts(sys->sprint("%c ", i));
		bout.puts(sys->sprint("%8bd\n", count[i]));
	}
	bout.flush();
}

