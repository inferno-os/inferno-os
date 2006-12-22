implement Disks;

# adapted from /sys/src/libdisk on Plan 9: subject to Lucent Public License 1.02

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "disks.m";

scsiverbose := 0;

Codefile: con "/lib/scsicodes";

Code: adt {
	v:	int;	# (asc<<8) | ascq
	s:	string;
};
codes: array of Code;

init()
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
}

#
# Discover the disk geometry by various sleazeful means.
# 
# First, if there is a partition table in sector 0,
# see if all the partitions have the same end head
# and sector; if so, we'll assume that that's the 
# right count.
# 
# If that fails, we'll try looking at the geometry that the ATA
# driver supplied, if any, and translate that as a
# BIOS might. 
# 
# If that too fails, which should only happen on a SCSI
# disk with no currently defined partitions, we'll try
# various common (h, s) pairs used by BIOSes when faking
# the geometries.
#

# table entry:
	Oactive,			# active flag
	Ostarth,			# starting head
	Ostarts,			# starting sector
	Ostartc,			# starting cylinder
	Otype,			# partition type
	Oendh,			# ending head
	Oends,			# ending sector
	Oendc: con iota;		# ending cylinder
	Oxlba: con Oendc+1;	# starting LBA from start of disc or partition [4]
	Oxsize: con Oxlba+4;	# size in sectors[4]

# Table: entry[NTentry][TentrySize] magic[2]
Omagic: con NTentry*TentrySize;

partitiongeometry(d: ref Disk): int
{
	buf := array[512] of byte;
	t := buf[Toffset:];

	#
	# look for an MBR first in the /dev/sdXX/data partition, otherwise
	# attempt to fall back on the current partition.
	#
	rawfd := sys->open(d.prefix+"data", Sys->OREAD);
	if(rawfd != nil
	&& sys->seek(rawfd, big 0, 0) == big 0
	&& readn(rawfd, buf, 512) == 512
	&& int t[Omagic] == Magic0
	&& int t[Omagic+1] == Magic1) {
		rawfd = nil;
	}else{
		rawfd = nil;
		if(sys->seek(d.fd, big 0, 0) < big 0
		|| readn(d.fd, buf, 512) != 512
		|| int t[Omagic] != Magic0
		|| int t[Omagic+1] != Magic1)
			return -1;
	}

	h := s := -1;
	for(i:=0; i<NTentry*TentrySize; i += TentrySize) {
		if(t[i+Otype] == byte 0)
			continue;

		t[i+Oends] &= byte 63;
		if(h == -1) {
			h = int t[i+Oendh];
			s = int t[i+Oends];
		} else {
			#
			# Only accept the partition info if every
			# partition is consistent.
			#
			if(h != int t[i+Oendh] || s != int t[i+Oends])
				return -1;
		}
	}

	if(h == -1)
		return -1;

	d.h = h+1;	# heads count from 0
	d.s = s;	# sectors count from 1
	d.c = int (d.secs / big (d.h*d.s));
	d.chssrc = "part";
	return 0;
}

#
# If there is ATA geometry, use it, perhaps massaged
#
drivergeometry(d: ref Disk): int
{
	if(d.c == 0 || d.h == 0 || d.s == 0)
		return -1;

	d.chssrc = "disk";
	if(d.c < 1024)
		return 0;

	case d.h {
	15 =>
		d.h = 255;
		d.c /= 17;

	* =>
		for(m := 2; m*d.h < 256; m *= 2) {
			if(d.c/m < 1024) {
				d.c /= m;
				d.h *= m;
				return 0;
			}
		}

		# set to 255, 63 and be done with it
		d.h = 255;
		d.s = 63;
		d.c = int (d.secs / big(d.h * d.s));
	}
	return 0;
}

#
# There's no ATA geometry and no partitions.
# Our guess is as good as anyone's.
#
Guess: adt {
	h:	int;
	s:	int;
};
guess: array of Guess = array[] of {
	(64, 32),
	(64, 63),
	(128, 63),
	(255, 63),
};

guessgeometry(d: ref Disk)
{
	d.chssrc = "guess";
	c := 1024;
	for(i:=0; i<len guess; i++)
		if(big(c*guess[i].h*guess[i].s) >= d.secs) {
			d.h = guess[i].h;
			d.s = guess[i].s;
			d.c = int(d.secs / big(d.h * d.s));
			return;
		}

	# use maximum values
	d.h = 255;
	d.s = 63;
	d.c = int(d.secs / big(d.h * d.s));
}

findgeometry(disk: ref Disk)
{
	disk.h = disk.s = disk.c = 0;
	if(partitiongeometry(disk) < 0 &&
	   drivergeometry(disk) < 0)
		guessgeometry(disk);
}

openfile(d: ref Disk): ref Disk
{
	(ok, db) := sys->fstat(d.fd);
	if(ok < 0)
		return nil;

	d.secsize = 512;
	d.size = db.length;
	d.secs = d.size / big d.secsize;
	d.offset = big 0;

	findgeometry(d);
	return mkwidth(d);
}

opensd(d: ref Disk): ref Disk
{
	b := bufio->fopen(d.ctlfd, Bufio->OREAD);
	while((p := b.gets('\n')) != nil){
		p = p[0:len p - 1];
		(nf, f) := sys->tokenize(p, " \t");	# might need str->unquote
		if(nf >= 3 && hd f == "geometry") {
			d.secsize = int hd tl tl f;
			if(nf >= 6) {
				d.c = int hd tl tl tl f;
				d.h = int hd tl tl tl tl f;
				d.s = int hd tl tl tl tl tl f;
			}
		}
		if(nf >= 4 && hd f == "part" && hd tl f == d.part) {
			d.offset = big hd tl tl f;
			d.secs = big hd tl tl tl f - d.offset;
		}
	}

	
	d.size = d.secs * big d.secsize;
	if(d.size <= big 0) {
		d.part = "";
		d.dtype = "file";
		return openfile(d);
	}

	findgeometry(d);
	return mkwidth(d);
}

Disk.open(name: string, mode: int, noctl: int): ref Disk
{
	d := ref Disk;
	d.rdonly = mode == Sys->OREAD;
	d.fd = sys->open(name, Sys->OREAD);
	if(d.fd == nil)
		return nil;

	if(mode != Sys->OREAD){
		d.wfd = sys->open(name, Sys->OWRITE);
		if(d.wfd == nil)
			d.rdonly = 1;
	}

	if(noctl)
		return openfile(d);

	# check for floppy(3) disk
	if(len name >= 7) {
		q := name[len name-7:];
		if(q[0] == 'f' && q[1] == 'd' && isdigit(q[2]) && q[3:] == "disk") {
			if((d.ctlfd = sys->open(name[0:len name-4]+"ctl", Sys->ORDWR)) != nil) {
				d.prefix = name[0:len name-4];	# fdN (unlike Plan 9)
				d.dtype = "floppy";
				return openfile(d);
			}
		}
	}

	# attempt to find sd(3) disk or partition
	d.prefix = name;
	for(i := len name; --i >= 0;)
		if(name[i] == '/'){
			d.prefix = name[0:i+1];
			break;
		}

	if((d.ctlfd = sys->open(d.prefix+"ctl", Sys->ORDWR)) != nil) {
		d.dtype = "sd";
		d.part = name[len d.prefix:];
		return opensd(d);
	}

	# assume we have just a normal file
	d.dtype = "file";
	return openfile(d);
}

mkwidth(d: ref Disk): ref Disk
{
	d.width = len sys->sprint("%bd", d.size);
	return d;
}

isdigit(c: int): int
{
	return c >= '0' && c <= '9';
}

putchs(d: ref Disk, p: array of byte, lba: big)
{
	s := int (lba % big d.s);
	h := int (lba / big d.s % big d.h);
	c := int (lba / (big d.s * big d.h));

	if(c >= 1024) {
		c = 1023;
		h = d.h - 1;
		s = d.s - 1;
	}

	p[0] = byte h;
	p[1] = byte (((s+1) & 16r3F) | ((c>>2) & 16rC0));
	p[2] = byte c;
}

PCpart.bytes(p: self PCpart, d: ref Disk): array of byte
{
	a := array[TentrySize] of byte;
	a[Oactive] = byte p.active;
	a[Otype] = byte p.ptype;
	putchs(d, a[Ostarth:], p.base+p.offset);
	putchs(d, a[Oendh:], p.base+p.offset+p.size-big 1);
	putle32(a[Oxlba:], p.offset);
	putle32(a[Oxsize:], p.size);
	return a;
}

PCpart.extract(a: array of byte, nil: ref Disk): PCpart
{
	p: PCpart;
	p.active = int a[Oactive];
	p.ptype = int a[Otype];
	p.base = big 0;
	p.offset = getle32(a[Oxlba:]);
	p.size = getle32(a[Oxsize:]);
	return p;
}

getle32(p: array of byte): big
{
	return (big p[3]<<24) | (big p[2]<<16) | (big p[1] << 8) | big p[0];
}

putle32(p: array of byte, i: big)
{
	p[0] = byte i;
	p[1] = byte (i>>8);
	p[2] = byte (i>>16);
	p[3] = byte (i>>24);
}

Disk.readn(d: self ref Disk, buf: array of byte, nb: int): int
{
	return readn(d.fd, buf, nb);
}

chstext(p: array of byte): string
{
	h := int p[0];
	c := int p[2];
	c |= (int p[1]&16rC0)<<2;
	s := (int p[1] & 16r3F);
	return sys->sprint("%d/%d/%d", c, h, s);
}

readn(fd: ref Sys->FD, buf: array of byte, nb: int): int
{
	for(nr := 0; nr < nb;){
		n := sys->read(fd, buf[nr:], nb-nr);
		if(n <= 0){
			if(nr == 0)
				return n;
			break;
		}
		nr += n;
	}
	return nr;
}
