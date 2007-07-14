implement Fdisk;

#
# fdisk - edit dos disk partition table
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "disks.m";
	disks: Disks;
	Disk, PCpart: import disks;
	NTentry, Toffset, TentrySize: import Disks;
	Magic0, Magic1: import Disks;

include "pedit.m";
	pedit: Pedit;
	Edit, Part: import pedit;

include "arg.m";

Fdisk: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Mpart: con 64;

blank := 0;
dowrite := 0;
file := 0;
rdonly := 0;
doauto := 0;
mbroffset := big 0;
printflag := 0;
printchs := 0;
sec2cyl := big 0;
written := 0;

edit: ref Edit;
stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	disks = load Disks Disks->PATH;
	pedit = load Pedit Pedit->PATH;

	sys->pctl(Sys->FORKFD, nil);
	disks->init();
	pedit->init();

	edit = Edit.mk("cylinder");

	edit.add = cmdadd;
	edit.del = cmddel;
	edit.okname = cmdokname;
	edit.ext = cmdext;
	edit.help = cmdhelp;
	edit.sum = cmdsum;
	edit.write = cmdwrite;
	edit.printctl = cmdprintctl;

	stderr = sys->fildes(2);

	secsize := 0;
	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("disk/fdisk [-abfprvw] [-s sectorsize] /dev/sdC0/data");
	while((o := arg->opt()) != 0)
		case o {
		'a' =>
			doauto++;
		'b' =>
			blank++;
		'f' =>
			file++;
		'p' =>
			printflag++;
		'r' =>
			rdonly++;
		's' =>
			secsize = int arg->earg();
		'v' =>
			printchs++;
		'w' =>
			dowrite++;
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	arg = nil;

	mode := Sys->ORDWR;
	if(rdonly)
		mode = Sys->OREAD;
	edit.disk = Disk.open(hd args, mode, file);
	if(edit.disk == nil) {
		sys->fprint(stderr, "cannot open disk: %r\n");
		exits("opendisk");
	}

	if(secsize != 0) {
		edit.disk.secsize = secsize;
		edit.disk.secs = edit.disk.size / big secsize;
	}

	sec2cyl = big (edit.disk.h * edit.disk.s);
	edit.end = edit.disk.secs / sec2cyl;

	findmbr(edit);

	if(blank)
		blankpart(edit);
	else
		rdpart(edit, big 0, big 0);

	if(doauto)
		autopart(edit);

	{
		if(dowrite)
			edit.runcmd("w");

		if(printflag)
			edit.runcmd("P");

		if(dowrite || printflag)
			exits(nil);

		sys->fprint(stderr, "cylinder = %bd bytes\n", sec2cyl*big edit.disk.secsize);
		edit.runcmd("p");
		for(;;) {
			sys->fprint(stderr, ">>> ");
			edit.runcmd(edit.getline());
		}
	}exception e{
	"*" =>
		sys->fprint(stderr, "fdisk: exception %q\n", e);
		if(written)
			recover(edit);
	}
}

Active:	con 16r80;		# partition is active
Primary:	con 16r01;		# internal flag

TypeBB:	con 16rFF;

TypeEMPTY:	con 16r00;
TypeFAT12:	con 16r01;
TypeXENIX:	con 16r02;		# root
TypeXENIXUSR:	con 16r03;		# usr
TypeFAT16:	con 16r04;
TypeEXTENDED:	con 16r05;
TypeFATHUGE:	con 16r06;
TypeHPFS:	con 16r07;
TypeAIXBOOT:	con 16r08;
TypeAIXDATA:	con 16r09;
TypeOS2BOOT:	con 16r0A;		# OS/2 Boot Manager
TypeFAT32:	con 16r0B;		# FAT 32
TypeFAT32LBA:	con 16r0C;		# FAT 32 needing LBA support
TypeEXTHUGE:	con 16r0F;		# FAT 32 extended partition
TypeUNFORMATTED:	con 16r16;		# unformatted primary partition (OS/2 FDISK)?
TypeHPFS2:	con 16r17;
TypeIBMRecovery:	con 16r1C;	# really hidden fat
TypeCPM0:	con 16r52;
TypeDMDDO:	con 16r54;		# Disk Manager Dynamic Disk Overlay
TypeGB:	con 16r56;		# ????
TypeSPEEDSTOR:	con 16r61;
TypeSYSV386:	con 16r63;		# also HURD?
TypeNETWARE:	con 16r64;
TypePCIX:	con 16r75;
TypeMINIX13:	con 16r80;		# Minix v1.3 and below
TypeMINIX:	con 16r81;		# Minix v1.5+
TypeLINUXSWAP:	con 16r82;
TypeLINUX:	con 16r83;
TypeLINUXEXT:	con 16r85;
TypeAMOEBA:	con 16r93;
TypeAMOEBABB:	con 16r94;
TypeBSD386:	con 16rA5;
TypeBSDI:	con 16rB7;
TypeBSDISWAP:	con 16rB8;
TypeOTHER:	con 16rDA;
TypeCPM:	con 16rDB;
TypeDellRecovery:	con 16rDE;
TypeSPEEDSTOR12:	con 16rE1;
TypeSPEEDSTOR16:	con 16rE4;
TypeLANSTEP:	con 16rFE;

Type9:	con Disks->Type9;

TableSize: con TentrySize*NTentry;
Omagic: con TableSize;

Type: adt {
	desc:	string;
	name:	string;
};

Dospart: adt {
	p:	ref Part;
	pc:	ref PCpart;
	primary:	int;
	lba:	big;	# absolute address
	size:	big;
};

Recover: adt {
	table:	array of byte;	# [TableSize+2] copy of table and magic
	lba:	big;	# where it came from
};

types: array of Type = array[256] of {
	TypeEMPTY =>		( "EMPTY", "" ),
	TypeFAT12 =>		( "FAT12", "dos" ),
	TypeFAT16 =>		( "FAT16", "dos" ),
	TypeFAT32 =>		( "FAT32", "dos" ),
	TypeFAT32LBA =>		( "FAT32LBA", "dos" ),
	TypeEXTHUGE =>		( "EXTHUGE", "" ),
	TypeIBMRecovery =>	( "IBMRECOVERY", "ibm" ),
	TypeEXTENDED =>		( "EXTENDED", "" ),
	TypeFATHUGE =>		( "FATHUGE", "dos" ),
	TypeBB =>		( "BB", "bb" ),

	TypeXENIX =>		( "XENIX", "xenix" ),
	TypeXENIXUSR =>		( "XENIX USR", "xenixusr" ),
	TypeHPFS =>		( "HPFS", "ntfs" ),
	TypeAIXBOOT =>		( "AIXBOOT", "aixboot" ),
	TypeAIXDATA =>		( "AIXDATA", "aixdata" ),
	TypeOS2BOOT =>		( "OS/2BOOT", "os2boot" ),
	TypeUNFORMATTED =>	( "UNFORMATTED", "" ),
	TypeHPFS2 =>		( "HPFS2", "hpfs2" ),
	TypeCPM0 =>		( "CPM0", "cpm0" ),
	TypeDMDDO =>		( "DMDDO", "dmdd0" ),
	TypeGB =>		( "GB", "gb" ),
	TypeSPEEDSTOR =>		( "SPEEDSTOR", "speedstor" ),
	TypeSYSV386 =>		( "SYSV386", "sysv386" ),
	TypeNETWARE =>		( "NETWARE", "netware" ),
	TypePCIX =>		( "PCIX", "pcix" ),
	TypeMINIX13 =>		( "MINIXV1.3", "minix13" ),
	TypeMINIX =>		( "MINIXV1.5", "minix15" ),
	TypeLINUXSWAP =>		( "LINUXSWAP", "linuxswap" ),
	TypeLINUX =>		( "LINUX", "linux" ),
	TypeLINUXEXT =>		( "LINUXEXTENDED", "" ),
	TypeAMOEBA =>		( "AMOEBA", "amoeba" ),
	TypeAMOEBABB =>		( "AMOEBABB", "amoebaboot" ),
	TypeBSD386 =>		( "BSD386", "bsd386" ),
	TypeBSDI =>		( "BSDI", "bsdi" ),
	TypeBSDISWAP =>		( "BSDISWAP", "bsdiswap" ),
	TypeOTHER =>		( "OTHER", "other" ),
	TypeCPM =>		( "CPM", "cpm" ),
	TypeDellRecovery =>	( "DELLRECOVERY", "dell" ),
	TypeSPEEDSTOR12 =>	( "SPEEDSTOR12", "speedstor" ),
	TypeSPEEDSTOR16 =>	( "SPEEDSTOR16", "speedstor" ),
	TypeLANSTEP =>		( "LANSTEP", "lanstep" ),

	Type9 =>			( "PLAN9", "plan9" ),

	* =>	(nil, nil),
};

dosparts: list of ref Dospart;

tag2part(p: ref Part): ref Dospart
{
	for(l := dosparts; l != nil; l = tl l)
		if((hd l).p.tag == p.tag)
			return hd l;
	raise "tag2part: cannot happen";
}

typestr0(ptype: int): string
{
	if(ptype < 0 || ptype >= len types || types[ptype].desc == nil)
		return sys->sprint("type %d", ptype);
	return types[ptype].desc;
}

gettable(disk: ref Disk, addr: big, mbr: int): array of byte
{
	table := array[TableSize+2] of {* => byte 0};
	diskread(disk, table, len table, addr, Toffset);
	if(mbr){
		# the informal specs say all must have this but apparently not, only mbr
		if(int table[Omagic] != Magic0 || int table[Omagic+1] != Magic1)
			sysfatal("did not find master boot record");
	}
	return table;
}

diskread(disk: ref Disk, data: array of byte, ndata: int, sec: big, off: int)
{
	a := sec*big disk.secsize + big off;
	if(sys->seek(disk.fd, a, 0) != a)
		sysfatal(sys->sprint("diskread seek %bud.%ud: %r", sec, off));
	if(sys->readn(disk.fd, data, ndata) != ndata)
		sysfatal(sys->sprint("diskread %ud at %bud.%ud: %r", ndata, sec, off));
}

puttable(disk: ref Disk, table: array of byte, sec: big): int
{
	return diskwrite(disk, table, len table, sec, Toffset);
}

diskwrite(disk: ref Disk, data: array of byte, ndata: int, sec: big, off: int): int
{
	written = 1;
	a := sec*big disk.secsize + big off;
	if(sys->seek(disk.wfd, a, 0) != a ||
	   sys->write(disk.wfd, data, ndata) != ndata){
		sys->fprint(stderr, "write %d bytes at %bud.%ud failed: %r\n", ndata, sec, off);
		return -1;
	}
	return 0;
}

partgen := 0;
parttag := 0;

mkpart(name: string, primary: int, lba: big, size: big, pcpart: ref PCpart): ref Dospart
{
	p := ref Dospart;
	if(name == nil){
		if(primary)
			c := 'p';
		else
			c = 's';
		name = sys->sprint("%c%d", c, ++partgen);
	}

	if(pcpart != nil)
		p.pc = pcpart;
	else
		p.pc = ref PCpart(0, 0, big 0, big 0, big 0);

	p.primary = primary;
	p.p = ref Part;	# TO DO
	p.p.name = name;
	p.p.start = lba/sec2cyl;
	p.p.end = (lba+size)/sec2cyl;
	p.p.ctlstart = lba;
	p.p.ctlend = lba+size;
	p.p.tag = ++parttag;
	p.lba = lba;	# absolute lba
	p.size = size;
	dosparts = p :: dosparts;
	return p;
}

#
# Recovery takes care of remembering what the various tables
# looked like when we started, attempting to restore them when
# we are finished.
#
rtabs: list of ref Recover;

addrecover(t: array of byte, lba: big)
{
	tc := array[TableSize+2] of byte;
	tc[0:] = t[0:len tc];
	rtabs = ref Recover(tc, lba) :: rtabs;
}

recover(edit: ref Edit)
{
	err := 0;
	for(rl := rtabs; rl != nil; rl = tl rl){
		r := hd rl;
		if(puttable(edit.disk, r.table, r.lba) < 0)
			err = 1;
	}
	if(err) {
		sys->fprint(stderr, "warning: some writes failed during restoration of old partition tables\n");
		exits("inconsistent");
	} else
		sys->fprint(stderr, "restored old partition tables\n");

	ctlfd := edit.disk.ctlfd;
	if(ctlfd != nil){
		offset := edit.disk.offset;
		for(i:=0; i<len edit.part; i++)
			if(edit.part[i].ctlname != nil && sys->fprint(ctlfd, "delpart %s", edit.part[i].ctlname)<0)
				sys->fprint(stderr, "delpart failed: %s: %r", edit.part[i].ctlname);
		for(i=0; i<len edit.ctlpart; i++)
			if(edit.part[i].name != nil && sys->fprint(ctlfd, "delpart %s", edit.ctlpart[i].name)<0)
				sys->fprint(stderr, "delpart failed: %s: %r", edit.ctlpart[i].name);
		for(i=0; i<len edit.ctlpart; i++){
			if(sys->fprint(ctlfd, "part %s %bd %bd", edit.ctlpart[i].name,
				edit.ctlpart[i].start+offset, edit.ctlpart[i].end+offset) < 0){
				sys->fprint(stderr, "restored disk partition table but not kernel; reboot\n");
				exits("inconsistent");
			}
		}
	}
	exits("restored");
}

#
# Read the partition table (including extended partition tables)
# from the disk into the part array.
#
rdpart(edit: ref Edit, lba: big, xbase: big)
{
	if(xbase == big 0)
		xbase = lba;	# extended partition in mbr sets the base

	table := gettable(edit.disk, mbroffset+lba, lba == big 0);
	addrecover(table, mbroffset+lba);

	for(tp := 0; tp<TableSize; tp += TentrySize){
		dp := PCpart.extract(table[tp:], edit.disk);
		case dp.ptype {
		TypeEMPTY =>
			;
		TypeEXTENDED or
		TypeEXTHUGE or
		TypeLINUXEXT =>
			rdpart(edit, xbase+dp.offset, xbase);
		* =>
			p := mkpart(nil, lba==big 0, lba+dp.offset, dp.size, ref dp);
			if((err := edit.addpart(p.p)) != nil)
				sys->fprint(stderr, "error adding partition: %s\n", err);
		}
	}
}

blankpart(edit: ref Edit)
{
	edit.changed = 1;
}

findmbr(edit: ref Edit)
{
	table := gettable(edit.disk, big 0, 1);
	for(tp := 0; tp < TableSize; tp += TentrySize){
		p := PCpart.extract(table[tp:], edit.disk);
		if(p.ptype == TypeDMDDO)
			mbroffset = big edit.disk.s;
	}
}

haveroom(edit: ref Edit, primary: int, start: big): int
{
	if(primary) {
		#
		# must be open primary slot.
		# primary slots are taken by primary partitions
		# and runs of secondary partitions.
		#
		n := 0;
		lastsec := 0;
		for(i:=0; i<len edit.part; i++) {
			p := tag2part(edit.part[i]);
			if(p.primary){
				n++;
				lastsec = 0;
			}else if(!lastsec){
				n++;
				lastsec = 1;
			}
		}
		return n<4;
	}

	#
	# secondary partitions can be inserted between two primary
	# partitions only if there is an empty primary slot.
	# otherwise, we can put a new secondary partition next
	# to a secondary partition no problem.
	#
	n := 0;
	for(i:=0; i<len edit.part; i++){
		p := tag2part(edit.part[i]);
		if(p.primary)
			n++;
		pend := p.p.end;
		q: ref Dospart;
		qstart: big;
		if(i+1<len edit.part){
			q = tag2part(edit.part[i+1]);
			qstart = q.p.start;
		}else{
			qstart = edit.end;
			q = nil;
		}
		if(start < pend || start >= qstart)
			continue;
		# we go between these two
		if(p.primary==0 || (q != nil && q.primary==0))
			return 1;
	}
	# not next to a secondary, need a new primary
	return n<4;
}

autopart(edit: ref Edit)
{
	for(i:=0; i<len edit.part; i++)
		if(tag2part(edit.part[i]).pc.ptype == Type9)
			return;

	# look for the biggest gap in which we can put a primary partition
	start := big 0;
	bigsize := big 0;
	bigstart := big 0;
	for(i=0; i<len edit.part; i++) {
		p := tag2part(edit.part[i]);
		if(p.p.start > start && p.p.start - start > bigsize && haveroom(edit, 1, start)) {
			bigsize = p.p.start - start;
			bigstart = start;
		}
		start = p.p.end;
	}

	if(edit.end - start > bigsize && haveroom(edit, 1, start)) {
		bigsize = edit.end - start;
		bigstart = start;
	}
	if(bigsize < big 1) {
		sys->fprint(stderr, "couldn't find space or partition slot for plan 9 partition\n");
		return;
	}

	# set new partition active only if no others are
	active := Active;	
	for(i=0; i<len edit.part; i++){
		p := tag2part(edit.part[i]);
		if(p.primary && p.pc.active & Active)
			active = 0;
	}

	# add new plan 9 partition
	bigsize *= sec2cyl;
	bigstart *= sec2cyl;
	if(bigstart == big 0) {
		bigstart += big edit.disk.s;
		bigsize -= big edit.disk.s;
	}
	p := mkpart(nil, 1, bigstart, bigsize, nil);
	p.p.changed = 1;
	p.pc.active = active;
	p.pc.ptype = Type9;
	edit.changed = 1;
	if((err := edit.addpart(p.p)) != nil){
		sys->fprint(stderr, "error adding plan9 partition: %s\n", err);
		return;
	}
}

namelist: list of string;

plan9print(part: ref Dospart, fd: ref Sys->FD)
{
	vname := types[part.pc.ptype].name;
	if(vname==nil) {
		part.p.ctlname = "";
		return;
	}

	start := mbroffset+part.lba;
	end := start+part.size;

	# avoid names like plan90
	i := len vname - 1;
	if(isdigit(vname[i]))
		sep := ".";
	else
		sep = "";

	i = 0;
	name := sys->sprint("%s", vname);
	ok: int;
	do {
		ok = 1;
		for(nl := namelist; nl != nil; nl = tl nl)
			if(name == hd nl) {
				i++;
				name = sys->sprint("%s%s%d", vname, sep, i);
				ok = 0;
			}
	} while(ok == 0);

	namelist = name :: namelist;
	part.p.ctlname = name;

	if(fd != nil)
		sys->print("part %s %bd %bd\n", name, start, end);
}

cmdprintctl(edit: ref Edit, ctlfd: ref Sys->FD)
{
	namelist = nil;
	for(i:=0; i<len edit.part; i++)
		plan9print(tag2part(edit.part[i]), nil);
	edit.ctldiff(ctlfd);
}

cmdokname(nil: ref Edit, name: string): string
{
	if(name[0] != 'p' && name[0] != 's' || len name < 2)
		return "name must be pN or sN";
	for(i := 1; i < len name; i++)
		if(!isdigit(name[i]))
			return "name must be pN or sN";

	return nil;
}

KB: con big 1024;
MB: con KB*KB;
GB: con KB*MB;

cmdsum(edit: ref Edit, vp: ref Part, a, b: big)
{
	if(vp != nil)
		p := tag2part(vp);

	qual: string;
	if(p != nil && p.p.changed)
		qual += "'";
	else
		qual += " ";
	if(p != nil && p.pc.active&Active)
		qual += "*";
	else
		qual += " ";

	if(p != nil)
		name := p.p.name;
	else
		name = "empty";
	if(p != nil)
		ty := " "+typestr0(p.pc.ptype);
	else
		ty = "";

	sz := (b-a)*big edit.disk.secsize*sec2cyl;
	suf := "B";
	div := big 1;
	if(sz >= big 1*GB){
		suf = "GB";
		div = GB;
	}else if(sz >= big 1*MB){
		suf = "MB";
		div = MB;
	}else if(sz >= big 1*KB){
		suf = "KB";
		div = KB;
	}

	if(div == big 1)
		sys->print("%s %-12s %*bd %-*bd (%bd cylinders, %bd %s)%s\n", qual, name,
			edit.disk.width, a, edit.disk.width, b, b-a, sz, suf, ty);
	else
		sys->print("%s %-12s %*bd %-*bd (%bd cylinders, %bd.%.2d %s)%s\n", qual, name,
			edit.disk.width, a, edit.disk.width, b,  b-a,
			sz/div, int(((sz%div)*big 100)/div), suf, ty);
}

cmdadd(edit: ref Edit, name: string, start: big, end: big): string
{
	if(!haveroom(edit, name[0]=='p', start))
		return "no room for partition";
	start *= sec2cyl;
	end *= sec2cyl;
	if(start == big 0 || name[0] != 'p')
		start += big edit.disk.s;
	p := mkpart(name, name[0]=='p', start, end-start, nil);
	p.p.changed = 1;
	p.pc.ptype = Type9;
	return edit.addpart(p.p);
}

cmddel(edit: ref Edit, p: ref Part): string
{
	return edit.delpart(p);
}

cmdwrite(edit: ref Edit): string
{
	wrpart(edit);
	return nil;
}

help: con
	"A name - set partition active\n"+
	"P - sys->print table in ctl format\n"+
	"R - restore disk back to initial configuration and exit\n"+
	"e - show empty dos partitions\n"+
	"t name [type] - set partition type\n";

cmdhelp(nil: ref Edit): string
{
	sys->print("%s\n", help);
	return nil;
}

cmdactive(edit: ref Edit, f: array of string): string
{
	if(len f != 2)
		return "args";

	if(f[1][0] != 'p')
		return "cannot set secondary partition active";

	if((p := tag2part(edit.findpart(f[1]))) == nil)
		return "unknown partition";

	for(i:=0; i<len edit.part; i++) {
		ip := tag2part(edit.part[i]);
		if(ip.pc.active & Active) {
			ip.pc.active &= ~Active;
			ip.p.changed = 1;
			edit.changed = 1;
		}
	}

	if((p.pc.active & Active) == 0) {
		p.pc.active |= Active;
		p.p.changed = 1;
		edit.changed = 1;
	}

	return nil;
}

strupr(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] >= 'a' && s[i] <= 'z')
			s[i] += 'A' - 'a';
	return s;
}

dumplist()
{
	n := 0;
	for(i:=0; i<len types; i++) {
		if(types[i].desc != nil) {
			sys->print("%-16s", types[i].desc);
			if(n++%4 == 3)
				sys->print("\n");
		}
	}
	if(n%4)
		sys->print("\n");
}

cmdtype(edit: ref Edit, f: array of string): string
{
	if(len f < 2)
		return "args";

	if((p := tag2part(edit.findpart(f[1]))) == nil)
		return "unknown partition";

	q: string;
	if(len f == 2) {
		for(;;) {
			sys->fprint(stderr, "new partition type [? for list]: ");
			q = edit.getline();
			if(q[0] == '?')
				dumplist();
			else
				break;
		}
	} else
		q = f[2];

	q = strupr(q);
	for(i:=0; i<len types; i++)
		if(types[i].desc != nil && types[i].desc == q)
			break;
	if(i < len types && p.pc.ptype != i) {
		p.pc.ptype = i;
		p.p.changed = 1;
		edit.changed = 1;
	}
	return nil;
}

cmdext(edit: ref Edit, f: array of string): string
{
	case f[0][0] {
	'A' =>
		return cmdactive(edit, f);
	't' =>
		return cmdtype(edit, f);
	'R' =>
		recover(edit);
		return nil;
	* =>
		return "unknown command";
	}
}

wrextend(edit: ref Edit, i: int, xbase: big, startlba: big): (int, big)
{
	if(i == len edit.part){
		endlba := edit.disk.secs;
		if(startlba < endlba)
			wrzerotab(edit.disk, mbroffset+startlba);
		return (i, endlba);
	}

	p := tag2part(edit.part[i]);
	if(p.primary){
		endlba := p.p.start*sec2cyl;
		if(startlba < endlba)
			wrzerotab(edit.disk, mbroffset+startlba);
		return (i, endlba);
	}

	disk := edit.disk;
	table := gettable(disk, mbroffset+startlba, 0);

	(ni, endlba) := wrextend(edit, i+1, xbase, p.p.end*sec2cyl);

	tp := wrtentry(disk, table[0:], p.pc.active, p.pc.ptype, startlba, startlba+big disk.s, p.p.end*sec2cyl);
	if(p.p.end*sec2cyl != endlba)
		tp += wrtentry(disk, table[tp:], 0, TypeEXTENDED, xbase, p.p.end*sec2cyl, endlba);

	for(; tp<TableSize; tp++)
		table[tp] = byte 0;

	table[Omagic] = byte Magic0;
	table[Omagic+1] = byte Magic1;

	if(puttable(edit.disk, table, mbroffset+startlba) < 0)
		recover(edit);
	return (ni, endlba);
}

wrzerotab(disk: ref Disk, addr: big)
{
	table := array[TableSize+2] of {Omagic => byte Magic0, Omagic+1 => byte Magic1, * => byte 0};
	if(puttable(disk, table, addr) < 0)
		recover(edit);
}

wrpart(edit: ref Edit)
{	
	disk := edit.disk;

	table := gettable(disk, mbroffset, 0);

	tp := 0;
	for(i:=0; i<len edit.part && tp<TableSize; ) {
		p := tag2part(edit.part[i]);
		if(p.p.start == big 0)
			s := big disk.s;
		else
			s = p.p.start*sec2cyl;
		if(p.primary) {
			tp += wrtentry(disk, table[tp:], p.pc.active, p.pc.ptype, big 0, s, p.p.end*sec2cyl);
			i++;
		}else{
			(ni, endlba) := wrextend(edit, i, p.p.start*sec2cyl, p.p.start*sec2cyl);
			if(endlba >= big 1024*sec2cyl)
				t := TypeEXTHUGE;
			else
				t = TypeEXTENDED;
			tp += wrtentry(disk, table[tp:], 0, t, big 0, s, endlba);
			i = ni;
		}
	}
	for(; tp<TableSize; tp++)
		table[tp] = byte 0;
		
	if(i != len edit.part)
		raise "wrpart: cannot happen #1";

	if(puttable(disk, table, mbroffset) < 0)
		recover(edit);

	# bring parts up to date
	namelist = nil;
	for(i=0; i<len edit.part; i++)
		plan9print(tag2part(edit.part[i]), nil);

	if(edit.ctldiff(disk.ctlfd) < 0)
		sys->fprint(stderr, "?warning: partitions could not be updated in devsd\n");
}

isdigit(c: int): int
{
	return c >= '0' && c <= '9';
}

sysfatal(s: string)
{
	sys->fprint(stderr, "fdisk: %s\n", s);
	raise "fail:error";
}

exits(s: string)
{
	if(s != nil)
		raise "fail:"+s;
	exit;
}

assert(i: int)
{
	if(!i)
		raise "assertion failed";
}

wrtentry(disk: ref Disk, entry: array of byte, active: int, ptype: int, xbase: big, lba: big, end: big): int
{
	pc: PCpart;
	pc.active = active;
	pc.ptype = ptype;
	pc.base = xbase;
	pc.offset = lba-xbase;
	pc.size = end-lba;
	entry[0:] = pc.bytes(disk);
	return TentrySize;
}
