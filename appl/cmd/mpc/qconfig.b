implement Configflash;

#
# this isn't a proper config program: it's currently just
# enough to set important parameters such as ethernet address.
# an extension is in the works.
# --chf

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

Configflash: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

Region: adt {
	base:	int;
	limit:	int;
};

#
# structure of allocation descriptor
#
Fcheck:	con 0;
Fbase:	con 4;
Flen:		con 8;
Ftag:		con 11;
Fsig:		con 12;
Fasize:	con 3*4+3+1;

Tdead:	con byte 0;
Tboot:	con byte 16r01;
Tconf:	con byte 16r02;
Tnone:	con byte 16rFF;

flashsig := array[] of {byte 16rF1, byte 16rA5, byte 16r5A, byte 16r1F};
noval := array[] of {0 to 3 =>byte 16rFF};	# 

Ctag, Cscreen, Cconsole, Cbaud, Cether, Cea, Cend: con iota;
config := array[] of {
	Ctag => "#plan9.ini\n",		# current flag for qboot, don't change
	Cscreen => "vgasize=640x480x8\n",
	Cconsole => "console=0 lcd\n",
	Cbaud => "baud=9600\n",
	Cether => "ether0=type=SCC port=2 ",	# note missing \n
	Cea => "ea=08003e400080\n",
	Cend => "\0"	# qboot currently requires it but shouldn't
};

Param: adt {
	name:	string;
	index:	int;
};

params := array[] of {
	Param("vgasize", Cscreen),
	Param("console", Cconsole),
	Param("ea", Cea),
	Param("baud", Cbaud)
};

# could come from file or #F/flash/flashctl
FLASHSEG: con 256*1024;
bootregion := Region(0, FLASHSEG);

stderr: ref Sys->FD;
prog := "qconfig";
damaged := 0;
debug := 0;

usage()
{
	sys->fprint(stderr, "Usage: %s [-D] [-f flash] [-param value ...]\n", prog);
	exit;
}

err(s: string)
{
	sys->fprint(stderr, "%s: %s", prog, s);
	if(!damaged)
		sys->fprint(stderr, "; flash not modified\n");
	else
		sys->fprint(stderr, "; flash might now be invalid\n");
	exit;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);
	if(args != nil){
		prog = hd args;
		args = tl args;
	}
	str = load String String->PATH;
	if(str == nil)
		err(sys->sprint("can't load %s: %r", String->PATH));
	flash := "#F/flash/flash";
	offset := 0;
	region := bootregion;
	
	for(; args != nil && (hd args)[0] == '-'; args = tl args)
		case a := hd args {
		"-f" =>
			(flash, args) = argf(tl args);
		"-D" =>
			debug = 1;
		* =>
			p := lookparam(params, a[1:]);
			if(p.index < 0)
				err(sys->sprint("unknown config parameter: %s", a));
			v: string;
			(v, args) = argf(tl args);
			config[p.index] = a[1:]+"="+v+"\n";	# would be nice to check it
		}
	if(len args > 0)
		usage();
	out := sys->open(flash, Sys->ORDWR);
	if(out == nil)
		err(sys->sprint("can't open %s for read/write: %r", flash));
	# TO DO: hunt for free space and add new entry
	plonk(out, FLASHSEG-Fasize, mkdesc(0, 128*1024, Tboot));
	c := flatten(config);
	if(debug)
		sys->print("%s", c);
	bconf := array of byte c;
	plonk(out, FLASHSEG-Fasize*2, mkdesc(128*1024, len bconf, Tconf));
	plonk(out, 128*1024, bconf);
}

argf(args: list of string): (string, list of string)
{
	if(args == nil)
		usage();
	return (hd args, args);
}

lookparam(options: array of Param, s: string): Param
{
	for(i := 0; i < len options; i++)
		if(options[i].name == s)
			return options[i];
	return Param(nil, -1);
}

flatten(a: array of string): string
{
	s := "";
	for(i := 0; i < len a; i++)
		s += a[i];
	return s;
}

plonk(out: ref Sys->FD, where: int, val: array of byte)
{
	if(debug){
		sys->print("write #%ux [%d]:", where, len val);
		for(i:=0; i<len val; i++)
			sys->print(" %.2ux", int val[i]);
		sys->print("\n");
	}
	sys->seek(out, big where, 0);
	if(sys->write(out, val, len val) != len val)
		err(sys->sprint("bad flash write: %r"));
}

cvt(v: int): array of byte
{
	a := array[4] of byte;
	a[0] = byte (v>>24);
	a[1] = byte (v>>16);
	a[2] = byte (v>>8);
	a[3] = byte (v & 16rff);
	return a;
}

mkdesc(base: int, length: int, tag: byte): array of byte
{
	a := array[Fasize] of byte;
	a[Fcheck:] = noval;
	a[Fbase:] = cvt(base);
	a[Flen:] = cvt(length)[1:];	# it's three bytes
	a[Ftag] = tag;
	a[Fsig:] = flashsig;
	return a;
}
