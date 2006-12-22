implement Compose, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	Report: import Reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Cmpchan,
	Nilentry, Option,
	Next, Down, Skip, Quit: import Fs;

Compose: module {};

AinB:	con 1<<3;
BinA:	con 1<<2;
AoutB:	con 1<<1;
BoutA:	con 1<<0;

A:		con AinB|AoutB;
AoverB:	con AinB|AoutB|BoutA;
AatopB:	con AinB|BoutA;
AxorB:	con AoutB|BoutA;

B:		con BinA|BoutA;
BoverA:	con BinA|BoutA|AoutB;
BatopA:	con BinA|AoutB;
BxorA:	con BoutA|AoutB;

ops := array[] of {
	AinB => "AinB",
	BinA => "BinA",
	AoutB => "AoutB",
	BoutA => "BoutA",
	A => "A",
	AoverB => "AoverB",
	AatopB => "AatopB",
	AxorB => "AxorB",
	B => "B",
	BoverA => "BoverA",
	BatopA => "BatopA",
};

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

types(): string
{
	return "ms-d";
}

init()
{
	sys = load Sys Sys->PATH;
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Fs->PATH);
	fs->init();
}

run(nil: ref Draw->Context, nil: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	c := chan of (ref Sys->Dir, ref Sys->Dir, chan of int);
	s := (hd args).s().i;
	for(i := 0; i < len ops; i++)
		if(ops[i] == s)
			break;
	if(i == len ops){
		sys->fprint(sys->fildes(2), "fs: join: bad op %q\n", s);
		return nil;
	}
	spawn compose(c, i, opts != nil);
	return ref Value.Vm(c);
}

compose(c: Cmpchan, op: int, dflag: int)
{
	t := array[4] of {* => 0};
	if(op & AinB)
		t[2r11] = 2r01;
	if(op & BinA)
		t[2r11] = 2r10;
	if(op & AoutB)
		t[2r01] = 2r01;
	if(op & BoutA)
		t[2r10] = 2r10;
	if(dflag){
		while(((d0, d1, reply) := <-c).t2 != nil){
			x := (d1 != nil) << 1 | d0 != nil;
			r := t[d0 != nil | (d1 != nil) << 1];
			if(r == 0 && x == 2r11 && (d0.mode & d1.mode & Sys->DMDIR))
				r = 2r11;
			reply <-= r;
		}
	}else{
		while(((d0, d1, reply) := <-c).t2 != nil)
			reply <-= t[(d1 != nil) << 1 | d0 != nil];
	}
}
