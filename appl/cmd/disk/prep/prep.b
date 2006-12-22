implement Prep;

#
# prepare plan 9/inferno disk partition
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "disks.m";
	disks: Disks;
	Disk: import disks;
	readn: import disks;

include "pedit.m";
	pedit: Pedit;
	Edit, Part: import pedit;

include "arg.m";

Prep: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

blank := 0;
file := 0;
doauto := 0;
printflag := 0;
opart: array of ref Part;
secbuf: array of byte;
osecbuf: array of byte;
zeroes: array of byte;
rdonly := 0;
dowrite := 0;

Prepedit: type Edit[string];

edit: ref Edit;

Auto: adt
{
	name:	string;
	min:		big;
	max:		big;
	weight:	int;
	alloc:	int;
	size:		big;
};

KB: con big 1024;
MB: con KB*KB;
GB: con KB*MB;

#
# Order matters -- this is the layout order on disk.
#
auto: array of Auto = array[] of {
	("9fat",		big 10*MB,	big 100*MB,	10, 0, big 0),
	("nvram",	big 512,	big 512,	1, 0, big 0),
	("fscfg",	big 512,	big 512,	1, 0, big 0),
	("fs",		big 200*MB,	big 0,	10, 0, big 0),
	("fossil",	big 200*MB,	big 0,	4, 0, big 0),
	("arenas",	big 500*MB,	big 0,	20, 0, big 0),
	("isect",	big 25*MB,	big 0,	1, 0, big 0),
	("other",	big 200*MB,	big 0,	4, 0, big 0),
	("swap",		big 100*MB,	big 512*MB,	1, 0, big 0),
	("cache",	big 50*MB,	big 1*GB,	2, 0, big 0),
};

stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	disks = load Disks Disks->PATH;
	pedit = load Pedit Pedit->PATH;

	sys->pctl(Sys->FORKFD, nil);
	disks->init();
	pedit->init();

	edit = Edit.mk("sector");

	edit.add = cmdadd;
	edit.del = cmddel;
	edit.okname = cmdokname;
	edit.sum = cmdsum;
	edit.write = cmdwrite;

	stderr = sys->fildes(2);
	secsize := 0;
	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("disk/prep [-bfprw] [-a partname]... [-s sectorsize] /dev/sdC0/plan9");
	while((o := arg->opt()) != 0)
		case o {
		'a' =>
			p := arg->earg();
			for(i:=0; i<len auto; i++){
				if(p == auto[i].name){
					if(auto[i].alloc){
						sys->fprint(stderr, "you said -a %s more than once.\n", p);
						arg->usage();
					}
					auto[i].alloc = 1;
					break;
				}
			}
			if(i == len auto){
				sys->fprint(stderr, "don't know how to create automatic partition %s\n", p);
				arg->usage();
			}
			doauto = 1;
		'b' =>
			blank++;
		'f' =>
			file++;
		'p' =>
			printflag++;
			rdonly++;
		'r' =>
			rdonly++;
		's' =>
			secsize = int arg->earg();
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
	disk := Disk.open(hd args, mode, file);
	if(disk == nil) {
		sys->fprint(stderr, "cannot open disk: %r\n");
		exits("opendisk");
	}

	if(secsize != 0) {
		disk.secsize = secsize;
		disk.secs = disk.size / big secsize;
	}
	edit.end = disk.secs;

	checkfat(disk);

	secbuf = array[disk.secsize+1] of byte;
	osecbuf = array[disk.secsize+1] of byte;
	zeroes = array[disk.secsize+1] of {* => byte 0};
	edit.disk = disk;

	if(blank == 0)
		rdpart(edit);

	# save old partition table
	opart = array[len edit.part] of ref Part;
	opart[0:] = edit.part;

	if(printflag) {
		edit.runcmd("P");
		exits(nil);
	}

	if(doauto)
		autopart(edit);

	if(dowrite) {
		edit.runcmd("w");
		exits(nil);
	}

	edit.runcmd("p");
	for(;;) {
		sys->fprint(stderr, ">>> ");
		edit.runcmd(edit.getline());
	}
}

cmdsum(edit: ref Edit, p: ref Part, a: big, b: big)
{
	c := ' ';
	name := "empty";
	if(p != nil){
		if(p.changed)
			c = '\'';
		name = p.name;
	}

	sz := (b-a)*big edit.disk.secsize;
	suf := "B ";
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
		sys->print("%c %-12s %*bd %-*bd (%bd sectors, %bd %s)\n", c, name,
			edit.disk.width, a, edit.disk.width, b, b-a, sz, suf);
	else
		sys->print("%c %-12s %*bd %-*bd (%bd sectors, %bd.%.2d %s)\n", c, name,
			edit.disk.width, a, edit.disk.width, b, b-a,
			sz/div, int (((sz%div)*big 100)/div), suf);
}

cmdadd(edit: ref Edit, name: string, start: big, end: big): string
{
	if(start < big 2 && name == "9fat")
		return "overlaps with the pbs and/or the partition table";

	return edit.addpart(mkpart(name, start, end, 1));
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

isfrog := array[256] of {
	byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,	# NUL
	byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,	# BKS
	byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,	# DLE
	byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1, byte 1,	# CAN
	' ' =>	byte 1,
	'/' =>	byte 1,
	16r7f=>	byte 1,
	* => byte 0
};

cmdokname(nil: ref Edit, elem: string): string
{
	for(i := 0; i < len elem; i++)
		if(int isfrog[elem[i]])
			return "bad character in name";
	return nil;
}

mkpart(name: string, start: big, end: big, changed: int): ref Part
{
	p := ref Part;
	p.name = name;
	p.ctlname = name;
	p.start = start;
	p.end = end;
	p.changed = changed;
	p.ctlstart = big 0;
	p.ctlend = big 0;
	return p;
}

# plan9 partition table is first sector of the disk

rdpart(edit: ref Edit)
{
	disk := edit.disk;
	sys->seek(disk.fd, big disk.secsize, 0);
	if(readn(disk.fd, osecbuf, disk.secsize) != disk.secsize)
		return;
	osecbuf[disk.secsize] = byte 0;
	secbuf[0:] = osecbuf;

	for(i := 0; i < disk.secsize; i++)
		if(secbuf[i] == byte 0)
			break;

	tab := string secbuf[0:i];
	if(len tab < 4 || tab[0:4] != "part"){
		sys->fprint(stderr, "no plan9 partition table found\n");
		return;
	}

	waserr := 0;
	(nline, lines) := sys->tokenize(tab, "\n");
	for(i=0; i<nline; i++){
		line := hd lines;
		lines = tl lines;
		if(len line < 4 || line[0:4] != "part"){
			waserr = 1;
			continue;
		}

		(nf, f) := sys->tokenize(line, " \t\r");
		if(nf != 4 || hd f != "part"){
			waserr = 1;
			continue;
		}

		a := big hd tl tl f;
		b := big hd tl tl tl f;
		if(a >= b){
			waserr = 1;
			continue;
		}

		if((err := edit.addpart(mkpart(hd tl f, a, b, 0))) != nil) {
			sys->fprint(stderr, "?%s: not continuing\n", err);
			exits("partition");
		}
	}
	if(waserr)
		sys->fprint(stderr, "syntax error reading partition\n");
}

min(a, b: big): big
{
	if(a < b)
		return a;
	return b;
}

autopart(edit: ref Edit)
{
	if(len edit.part > 0) {
		if(doauto)
			sys->fprint(stderr, "partitions already exist; not repartitioning\n");
		return;
	}

	secs := edit.disk.secs;
	secsize := big edit.disk.secsize;
	for(;;){
		# compute total weights
		totw := 0;
		for(i:=0; i<len auto; i++){
			if(auto[i].alloc==0 || auto[i].size != big 0)
				continue;
			totw += auto[i].weight;
		}
		if(totw == 0)
			break;

		if(secs <= big 0){
			sys->fprint(stderr, "ran out of disk space during autopartition.\n");
			return;
		}

		# assign any minimums for small disks
		futz := 0;
		for(i=0; i<len auto; i++){
			if(auto[i].alloc==0 || auto[i].size != big 0)
				continue;
			s := (secs*big auto[i].weight)/big totw;
			if(s < big auto[i].min/secsize){
				auto[i].size = big auto[i].min/secsize;
				secs -= auto[i].size;
				futz = 1;
				break;
			}
		}
		if(futz)
			continue;

		# assign any maximums for big disks
		futz = 0;
		for(i=0; i<len auto; i++){
			if(auto[i].alloc==0 || auto[i].size != big 0)
				continue;
			s := (secs*big auto[i].weight)/big totw;
			if(auto[i].max != big 0 && s > auto[i].max/secsize){
				auto[i].size = auto[i].max/secsize;
				secs -= auto[i].size;
				futz = 1;
				break;
			}
		}
		if(futz)
			continue;

		# finally, assign partition sizes according to weights
		for(i=0; i<len auto; i++){
			if(auto[i].alloc==0 || auto[i].size != big 0)
				continue;
			s := (secs*big auto[i].weight)/big totw;
			auto[i].size = s;

			# use entire disk even in face of rounding errors
			secs -= auto[i].size;
			totw -= auto[i].weight;
		}
	}

	for(i:=0; i<len auto; i++)
		if(auto[i].alloc)
			sys->print("%s %bud\n", auto[i].name, auto[i].size);

	s := big 0;
	for(i=0; i<len auto; i++){
		if(auto[i].alloc == 0)
			continue;
		if((err := edit.addpart(mkpart(auto[i].name, s, s+auto[i].size, 1))) != nil)
			sys->fprint(stderr, "addpart %s: %s\n", auto[i].name, err);
		s += auto[i].size;
	}
}

restore(edit: ref Edit, ctlfd: ref Sys->FD)
{
	offset := edit.disk.offset;
	sys->fprint(stderr, "attempting to restore partitions to previous state\n");
	if(sys->seek(edit.disk.wfd, big edit.disk.secsize, 0) != big 0){
		sys->fprint(stderr, "cannot restore: error seeking on disk: %r\n");
		exits("inconsistent");
	}

	if(sys->write(edit.disk.wfd, osecbuf, edit.disk.secsize) != edit.disk.secsize){
		sys->fprint(stderr, "cannot restore: couldn't write old partition table to disk: %r\n");
		exits("inconsistent");
	}

	if(ctlfd != nil){
		for(i:=0; i<len edit.part; i++)
			sys->fprint(ctlfd, "delpart %s", edit.part[i].name);
		for(i=0; i<len opart; i++){
			if(sys->fprint(ctlfd, "part %s %bd %bd", opart[i].name, opart[i].start+offset, opart[i].end+offset) < 0){
				sys->fprint(stderr, "restored disk partition table but not kernel table; reboot\n");
				exits("inconsistent");
			}
		}
	}
	exits("restored");
}

wrpart(edit: ref Edit)
{
	disk := edit.disk;

	secbuf[0:] = zeroes;
	n := 0;
	for(i:=0; i<len edit.part; i++){
		a := sys->aprint("part %s %bd %bd\n", 
			edit.part[i].name, edit.part[i].start, edit.part[i].end);
		if(n + len a > disk.secsize){
			sys->fprint(stderr, "partition table bigger than sector (%d bytes)\n", disk.secsize);
			exits("overflow");
		}
		secbuf[n:] = a;
		n += len a;
	}

	if(sys->seek(disk.wfd, big disk.secsize, 0) != big disk.secsize){
		sys->fprint(stderr, "error seeking to %d on disk: %r\n", disk.secsize);
		exits("seek");
	}

	if(sys->write(disk.wfd, secbuf, disk.secsize) != disk.secsize){
		sys->fprint(stderr, "error writing partition table to disk: %r\n");
		restore(edit, nil);
	}

	if(edit.ctldiff(disk.ctlfd) < 0)
		sys->fprint(stderr, "?warning: partitions could not be updated in devsd\n");
}

#
# Look for a boot sector in sector 1, as would be
# the case if editing /dev/sdC0/data when that
# was really a bootable disk.
#
checkfat(disk: ref Disk)
{
	buf := array[32] of byte;

	if(sys->seek(disk.fd, big disk.secsize, 0) != big disk.secsize ||
	   sys->read(disk.fd, buf, len buf) < len buf)
		return;

	if(buf[0] != byte 16rEB || buf[1] != byte 16r3C || buf[2] != byte 16r90)
		return;

	sys->fprint(stderr, 
		"there's a fat partition where the\n"+
		"plan9 partition table would go.\n"+
		"if you really want to overwrite it, zero\n"+
		"the second sector of the disk and try again\n");

	exits("fat partition");
}

exits(s: string)
{
	if(s != nil)
		raise "fail:"+s;
	exit;
}
