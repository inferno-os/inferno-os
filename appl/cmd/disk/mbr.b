implement Mbr;

#
# install new master boot record boot code on PC disk.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "disks.m";
	disks: Disks;
	Disk, PCpart, Toffset: import disks;

include "arg.m";

Mbr: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};



#
# Default boot block prints an error message and reboots. 
#
ndefmbr := Toffset;
defmbr := array[512] of {
	byte 16rEB, byte 16r3C, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00,
	byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00,
16r03E => byte 16rFA, byte 16rFC, byte 16r8C, byte 16rC8, byte 16r8E, byte 16rD8, byte 16r8E, byte 16rD0,
	byte 16rBC, byte 16r00, byte 16r7C, byte 16rBE, byte 16r77, byte 16r7C, byte 16rE8, byte 16r19,
	byte 16r00, byte 16r33, byte 16rC0, byte 16rCD, byte 16r16, byte 16rBB, byte 16r40, byte 16r00,
	byte 16r8E, byte 16rC3, byte 16rBB, byte 16r72, byte 16r00, byte 16rB8, byte 16r34, byte 16r12,
	byte 16r26, byte 16r89, byte 16r07, byte 16rEA, byte 16r00, byte 16r00, byte 16rFF, byte 16rFF,
	byte 16rEB, byte 16rD6, byte 16rAC, byte 16r0A, byte 16rC0, byte 16r74, byte 16r09, byte 16rB4,
	byte 16r0E, byte 16rBB, byte 16r07, byte 16r00, byte 16rCD, byte 16r10, byte 16rEB, byte 16rF2,
	byte 16rC3,  byte 'N',  byte 'o',  byte 't',  byte ' ',  byte 'a',  byte ' ',  byte 'b',
	 byte 'o',  byte 'o',  byte 't',  byte 'a',  byte 'b',  byte 'l',  byte 'e',  byte ' ',
	 byte 'd',  byte 'i',  byte 's',  byte 'c',  byte ' ',  byte 'o',  byte 'r',  byte ' ',
	 byte 'd',  byte 'i',  byte 's',  byte 'c',  byte ' ',  byte 'e',  byte 'r',  byte 'r',
	 byte 'o',  byte 'r', byte '\r', byte '\n',  byte 'P',  byte 'r',  byte 'e',  byte 's',
	 byte 's',  byte ' ',  byte 'a',  byte 'l',  byte 'm',  byte 'o',  byte 's',  byte 't',
	 byte ' ',  byte 'a',  byte 'n',  byte 'y',  byte ' ',  byte 'k',  byte 'e',  byte 'y',
	 byte ' ',  byte 't',  byte 'o',  byte ' ',  byte 'r',  byte 'e',  byte 'b',  byte 'o',
	 byte 'o',  byte 't',  byte '.',  byte '.',  byte '.', byte 16r00, byte 16r00, byte 16r00,
};

init(nil: ref Draw->Context, args: list of string)
{
	flag9 := 0;
	mbrfile: string;
	sys = load Sys Sys->PATH;
	disks = load Disks Disks->PATH;

	sys->pctl(Sys->FORKFD, nil);
	disks->init();

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("disk/mbr [-m mbrfile] disk");
	while((o := arg->opt()) != 0)
		case o {
		'9' =>
			flag9 = 1;
		'm' =>
			mbrfile = arg->earg();
		* =>
			arg->usage();
		} 
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	arg = nil;

	disk := Disk.open(hd args, Sys->ORDWR, 0);
	if(disk == nil)
		fatal(sys->sprint("opendisk %s: %r", hd args));

	if(disk.dtype == "floppy")
		fatal(sys->sprint("will not install mbr on floppy"));
	if(disk.secsize != 512)
		fatal(sys->sprint("secsize %d invalid: must be 512", disk.secsize));

	secsize := disk.secsize;
	mbr := array[secsize*disk.s] of {* => byte 0};

	#
	# Start with initial sector from disk.
	#
	if(sys->seek(disk.fd, big 0, 0) < big 0)
		fatal(sys->sprint("seek to boot sector: %r\n"));
	if(sys->read(disk.fd, mbr, secsize) != secsize)
		fatal(sys->sprint("reading boot sector: %r"));

	nmbr: int;
	if(mbrfile == nil){
		nmbr = ndefmbr;
		mbr[0:] = defmbr;
	} else {
		buf := array[secsize*(disk.s+1)] of {* => byte 0};
		if((sysfd := sys->open(mbrfile, Sys->OREAD)) == nil)
			fatal(sys->sprint("open %s: %r", mbrfile));
		if((nmbr = sys->read(sysfd, buf, secsize*(disk.s+1))) < 0)
			fatal(sys->sprint("read %s: %r", mbrfile));
		if(nmbr > secsize*disk.s)
			fatal(sys->sprint("master boot record too large %d > %d", nmbr, secsize*disk.s));
		if(nmbr < secsize)
			nmbr = secsize;
		sysfd = nil;
		buf[Toffset:] = mbr[Toffset:secsize];
		mbr[0:] = buf[0:nmbr];
	}

	if(flag9){
		for(i := Toffset; i < secsize; i++)
			mbr[i] = byte 0;
		mbr[Toffset:] = PCpart(0, Disks->Type9, big 0, big disk.s, disk.secs-big disk.s).bytes(disk);
	}
	mbr[secsize-2] = byte Disks->Magic0;
	mbr[secsize-1] = byte Disks->Magic1;
	nmbr = (nmbr+secsize-1)&~(secsize-1);
	if(sys->seek(disk.wfd, big 0, 0) < big 0)
		fatal(sys->sprint("seek to MBR sector: %r\n"));
	if(sys->write(disk.wfd, mbr, nmbr) != nmbr)
		fatal(sys->sprint("writing MBR: %r"));
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "disk/mbr: %s\n", s);
	raise "fail:error";
}
