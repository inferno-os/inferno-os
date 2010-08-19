implement Ar;

#
# ar - portable (ascii) format version
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "daytime.m";
	daytime: Daytime;

include "string.m";
	str: String;

Ar: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

ARMAG: con "!<arch>\n";
SARMAG: con len ARMAG;
ARFMAG0: con byte '`';
ARFMAG1: con byte '\n';
SARNAME: con 16;	# ancient limit

#
# printable archive header
#	name[SARNAME] date[12] uid[6] gid[6] mode[8] size[10] fmag[2]
#
Oname:	con 0;
Lname:	con SARNAME;
Odate:	con Oname+Lname;
Ldate:	con 12;
Ouid:	con Odate+Ldate;
Luid:		con 6;
Ogid:	con Ouid+Luid;
Lgid:		con 6;
Omode:	con Ogid+Lgid;
Lmode:	con 8;
Osize:	con Omode+Lmode;
Lsize:	con 10;
Ofmag:	con Osize+Lsize;
Lfmag:	con 2;
SAR_HDR:	con Ofmag+Lfmag;	# 60

#
# 	The algorithm uses up to 3 temp files.  The "pivot contents" is the
# 	archive contents specified by an a, b, or i option.  The temp files are
# 	astart - contains existing contentss up to and including the pivot contents.
# 	amiddle - contains new files moved or inserted behind the pivot.
# 	aend - contains the existing contentss that follow the pivot contents.
# 	When all contentss have been processed, function 'install' streams the
#  	temp files, in order, back into the archive.
#

Armember: adt {	# one per archive contents
	name:	string;	# trimmed
	length:	int;
	date:	int;
	uid:	int;
	gid:	int;
	mode:	int;
	size:	int;
	contents:	array of byte;
	fd:	ref Sys->FD;	# if contents is nil and fd is not nil, fd has contents
	next:	cyclic ref Armember;

	new:		fn(name: string, fd: ref Sys->FD): ref Armember;
	rdhdr:	fn(b: ref Iobuf): ref Armember;
	read:		fn(m: self ref Armember, b:  ref Iobuf): int;
	wrhdr:	fn(m: self ref Armember, fd: ref Sys->FD);
	write:	fn(m: self ref Armember, fd: ref Sys->FD);
	skip:		fn(m: self ref Armember, b: ref Iobuf);
	replace:	fn(m: self ref Armember, name: string, fd: ref Sys->FD);
	copyout:	fn(m: self ref Armember, b: ref Iobuf, destfd: ref Sys->FD);
};

Arfile: adt {	# one per tempfile
	fd:	ref Sys->FD;	# paging file descriptor, nil if none allocated

	head:	ref Armember;
	tail:	ref Armember;

	new:		fn(): ref Arfile;
	copy:	fn(ar: self ref Arfile, b: ref Iobuf, mem: ref Armember);
	insert:	fn(ar: self ref Arfile, mem: ref Armember);
	stream:	fn(ar: self ref Arfile, fd: ref Sys->FD);
	page:	fn(ar: self ref Arfile): int;
};

File: adt {
	name:	string;
	trimmed:	string;
	found:	int;
};

man :=	"mrxtdpq";
opt :=	"uvnbailo";

aflag := 0;
bflag := 0;
cflag := 0;
oflag := 0;
uflag := 0;
vflag := 0;

pivotname: string;
bout: ref Iobuf;
stderr: ref Sys->FD;
parts: array of ref Arfile;

comfun: ref fn(a: string, f: array of ref File);

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;
	str = load String String->PATH;

	stderr = sys->fildes(2);
	bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
	if(len args < 3)
		usage();
	args = tl args;
	s := hd args; args = tl args;
	for(i := 0; i < len s; i++){
		case s[i] {
		'a' =>	aflag = 1;
		'b' =>	bflag = 1;
		'c' =>	cflag = 1;
		'd' =>	setcom(dcmd);
		'i' =>		bflag = 1;
		'l' =>		;	# ignored
		'm' =>	setcom(mcmd);
		'o' =>	oflag = 1;
		'p' =>	setcom(pcmd);
		'q' =>	setcom(qcmd);
		'r' =>		setcom(rcmd);
		't' =>		setcom(tcmd);
		'u' =>	uflag = 1;
		'v' =>	vflag = 1;
		'x' =>	setcom(xcmd);
		* =>
			sys->fprint(stderr, "ar: bad option `%c'\n", s[i]);
			usage();
		}
	}
	if(aflag && bflag){
		sys->fprint(stderr, "ar: only one of 'a' and 'b' can be specified\n");
		usage();
	}
	if(aflag || bflag){
		pivotname = trim(hd args); args = tl args;
		if(len args < 2)
			usage();
	}
	if(comfun == nil){
		if(uflag == 0){
			sys->fprint(stderr, "ar: one of [%s] must be specified\n", man);
			usage();
		}
		setcom(rcmd);
	}
	cp := hd args; args = tl args;
	files := array[len args] of ref File;
	for(i = 0; args != nil; args = tl args)
		files[i++] = ref File(hd args, trim(hd args), 0);
	comfun(cp, files);	# do the command
	allfound := 1;
	for(i = 0; i < len files; i++)
		if(!files[i].found){
			sys->fprint(stderr, "ar: %s not found\n", files[i].name);
			allfound = 0;
		}
	bout.flush();
	if(!allfound)
		raise "fail: file not found";
}

#
# 	select a command
#
setcom(fun: ref fn(s: string, f: array of ref File))
{
	if(comfun != nil){
		sys->fprint(stderr, "ar: only one of [%s] allowed\n", man);
		usage();
	}
	comfun = fun;
}

#
# 	perform the 'r' and 'u' commands
#
rcmd(arname: string, files: array of ref File)
{
	bar := openar(arname, Sys->ORDWR, 1);
	parts = array[2] of {Arfile.new(), nil};
	ap := parts[0];
	if(bar != nil){
		while((mem := Armember.rdhdr(bar)) != nil){
			if(bamatch(mem.name, pivotname))	# check for pivot
				ap = parts[1] = Arfile.new();
			f := match(files, mem.name);
			if(f == nil){
				ap.copy(bar, mem);
				continue;
			}
			f.found = 1;
			dfd := sys->open(f.name, Sys->OREAD);
			if(dfd == nil){
				if(len files > 0)
					sys->fprint(stderr, "ar: cannot open %s: %r\n", f.name);
				ap.copy(bar, mem);
				continue;
			}
			if(uflag){
				(ok, d) := sys->fstat(dfd);
				if(ok < 0 || d.mtime <= mem.date){
					if(ok < 0)
						sys->fprint(stderr, "ar: cannot stat %s: %r\n", f.name);
					ap.copy(bar, mem);
					continue;
				}
			}
			mem.skip(bar);
			mesg('r', f.name);
			mem.replace(f.name, dfd);
			ap.insert(mem);
			dfd = nil;
		}
	}
	# copy in remaining files named on command line
	for(i := 0; i < len files; i++){
		f := files[i];
		if(f.found)
			continue;
		f.found = 1;
		dfd := sys->open(f.name, Sys->OREAD);
		if(dfd != nil){
			mesg('a', f.name);
			parts[0].insert(Armember.new(f.trimmed, dfd));
		}else
			sys->fprint(stderr, "ar: cannot open %s: %r\n", f.name);
	}
	if(bar == nil && !cflag)
		install(arname, parts, 1);	# issue 'creating' msg
	else
		install(arname, parts, 0);
}

dcmd(arname: string, files: array of ref File)
{
	if(len files == 0)
		return;
	changed := 0;
	parts = array[] of {Arfile.new()};
	bar := openar(arname, Sys->ORDWR, 0);
	while((mem := Armember.rdhdr(bar)) != nil){
		if(match(files, mem.name) != nil){
			mesg('d', mem.name);
			mem.skip(bar);
			changed = 1;
		}else
			parts[0].copy(bar, mem);
		mem =  nil;	# conserves memory
	}
	if(changed)
		install(arname, parts, 0);
}

xcmd(arname: string, files: array of ref File)
{
	bar := openar(arname, Sys->OREAD, 0);
	i := 0;
	while((mem := Armember.rdhdr(bar)) != nil){
		if((f := match(files, mem.name)) != nil){
			f.found = 1;
			fd := sys->create(f.name, Sys->OWRITE, mem.mode & 8r777);
			if(fd == nil){
				sys->fprint(stderr, "ar: cannot create %s: %r\n", f.name);
				mem.skip(bar);
			}else{
				mesg('x', f.name);
				mem.copyout(bar, fd);
				if(oflag){
					dx := sys->nulldir;
					dx.atime = mem.date;
					dx.mtime = mem.date;
					if(sys->fwstat(fd, dx) < 0)
						sys->fprint(stderr, "ar: can't set times on %s: %r", f.name);
				}
				fd = nil;
				mem = nil;
			}
			if(len files > 0 && ++i >= len files)
				break;
		}else
			mem.skip(bar);
	}
}

pcmd(arname: string, files: array of ref File)
{
	bar := openar(arname, Sys->OREAD, 0);
	i := 0;
	while((mem := Armember.rdhdr(bar)) != nil){
		if((f := match(files, mem.name)) != nil){
			if(vflag)
				sys->print("\n<%s>\n\n", f.name);
			mem.copyout(bar, sys->fildes(1));
			if(len files > 0 && ++i >= len files)
				break;
		}else
			mem.skip(bar);
		mem = nil;	# we no longer need the contents
	}
}

mcmd(arname: string, files: array of ref File)
{
	if(len files == 0)
		return;
	parts = array[3] of {Arfile.new(), Arfile.new(), nil};
	bar := openar(arname, Sys->ORDWR, 0);
	ap := parts[0];
	while((mem := Armember.rdhdr(bar)) != nil){
		if(bamatch(mem.name, pivotname))
			ap = parts[2] = Arfile.new();
		if((f := match(files, mem.name)) != nil){
			mesg('m', f.name);
			parts[1].copy(bar, mem);
		}else
			ap.copy(bar, mem);
	}
	if(pivotname != nil && parts[2] == nil)
		sys->fprint(stderr, "ar: %s not found - files moved to end\n", pivotname);
	install(arname, parts, 0);
}

tcmd(arname: string, files: array of ref File)
{
	bar := openar(arname, Sys->OREAD, 0);
	while((mem := Armember.rdhdr(bar)) != nil){
		if((f := match(files, mem.name)) != nil){
			longls := "";
			if(vflag)
				longls = longtext(mem)+" ";
			bout.puts(longls+f.trimmed+"\n");
		}
		mem.skip(bar);
		mem = nil;
	}
}

qcmd(arname: string, files: array of ref File)
{
	if(aflag || bflag){
		sys->fprint(stderr, "ar: abi not allowed with q\n");
		raise "fail:usage";
	}
	fd := openrawar(arname, Sys->ORDWR, 1);
	if(fd == nil){
		if(!cflag)
			sys->fprint(stderr, "ar: creating %s\n", arname);
		fd = arcreate(arname);
	}
	# leave note group behind when writing archive; i.e. sidestep interrupts
	sys->seek(fd, big 0, 2);	# append
	for(i := 0; i < len files; i++){
		f := files[i];
		f.found = 1;
		dfd := sys->open(f.name, Sys->OREAD);
		if(dfd != nil){
			mesg('q', f.name);
			mem := Armember.new(f.trimmed, dfd);
			if(mem != nil){
				mem.write(fd);
				mem = nil;
			}
		}else
			sys->fprint(stderr, "ar: cannot open %s: %r\n", f.name);
	}
}

#
# 	open an archive and validate its header
#
openrawar(arname: string, mode: int, errok: int): ref Sys->FD
{
	fd := sys->open(arname, mode);
	if(fd == nil){
		if(!errok){
			sys->fprint(stderr, "ar: cannot open %s: %r\n", arname);
			raise "fail:error";
		}
		return nil;
	}
	mbuf := array[SARMAG] of byte;
	if(sys->read(fd, mbuf, SARMAG) != SARMAG || string mbuf != ARMAG){
		sys->fprint(stderr, "ar: %s not in archive format\n", arname);
		raise "fail:error";
	}
	return fd;
}

openar(arname: string, mode: int, errok: int): ref Iobuf
{
	fd := openrawar(arname, mode, errok);
	if(fd == nil)
		return nil;
	bfd := bufio->fopen(fd, mode);
	bfd.seek(big SARMAG, 0);
	return bfd;
}

#
# 	create an archive and set its header
#
arcreate(arname: string): ref Sys->FD
{
	fd := sys->create(arname, Sys->OWRITE, 8r666);
	if(fd == nil){
		sys->fprint(stderr, "ar: cannot create %s: %r\n", arname);
		raise "fail:create";
	}
	a := array of byte ARMAG;
	mustwrite(fd, a, len a);
	return fd;
}

#
# 		error handling
#
wrerr()
{
	sys->fprint(stderr, "ar: write error: %r\n");
	raise "fail:write error";
}

rderr()
{
	sys->fprint(stderr, "ar: read error: %r\n");
	raise "fail:read error";
}

phaseerr(offset: big)
{
	sys->fprint(stderr, "ar: phase error at offset %bd\n", offset);
	raise "fail:phase error";
}

usage()
{
	sys->fprint(stderr, "usage: ar [%s][%s] archive files ...\n", opt, man);
	raise "fail:usage";
}

#
# concatenate the several sequences of members into one archive
#
install(arname: string, seqs: array of ref Arfile, createflag: int)
{
	# leave process group behind when copying back; i.e. sidestep interrupts
	sys->pctl(Sys->NEWPGRP, nil);

	if(createflag)
		sys->fprint(stderr, "ar: creating %s\n", arname);
	fd := arcreate(arname);
	for(i := 0; i < len seqs; i++)
		if((ap := seqs[i]) != nil)
			ap.stream(fd);
}

#
# return the command line File matching a given name
#
match(files: array of ref File, file: string): ref File
{
	if(len files == 0)
		return ref File(file, file, 0);	# empty list always matches
	for(i := 0; i < len files; i++)
		if(!files[i].found && files[i].trimmed == file){
			files[i].found = 1;
			return files[i];
		}
	return nil;
}

#
# is `file' the pivot member's name and is the archive positioned
# at the correct point wrt after or before options?  return true if so.
#
state := 0;

bamatch(file: string, pivot: string): int
{
	case state {
	0 =>			# looking for position file
		if(aflag){
			if(file == pivot)
				state = 1;
		}else if(bflag){
			if(file == pivot){
				state = 2;	# found
				return 1;
			}
		}
	1 =>			# found - after previous file
		state = 2;
		return 1;
	2 =>			# already found position file
		;
	}
	return 0;
}

#
# output a message, if 'v' option was specified
#
mesg(c: int, file: string)
{
	if(vflag)
		bout.puts(sys->sprint("%c - %s\n", c, file));
}

#
# return just the file name
#
trim(s: string): string
{
	for(j := len s; j > 0 && s[j-1] == '/';)
		j--;
	k := 0;
	for(i := 0; i < j; i++)
		if(s[i] == '/')
			k = i+1;
	return s[k: j];
}

longtext(mem: ref Armember): string
{
	s := modes(mem.mode);
	s += sys->sprint(" %3d/%1d", mem.uid, mem.gid);
	s += sys->sprint(" %7ud", mem.size);
	t := daytime->text(daytime->local(mem.date));
	return s+sys->sprint(" %-12.12s %-4.4s ", t[4:], t[24:]);
}

mtab := array[] of {
	"---",	"--x",	"-w-",	"-wx",
	"r--",	"r-x",	"rw-",	"rwx"
};

modes(mode: int): string
{
	return mtab[(mode>>6)&7]+mtab[(mode>>3)&7]+mtab[mode&7];
}

#
# read the header for the next archive contents
#
Armember.rdhdr(b: ref Iobuf): ref Armember
{
	buf := array[SAR_HDR] of byte;
	if((n := b.read(buf, len buf)) != len buf){
		if(n == 0)
			return nil;
		if(n > 0)
			sys->werrstr("unexpected end-of-file");
		rderr();
	}
	mem := ref Armember;
	for(i := Oname+Lname; i > Oname; i--)
		if(buf[i-1] != byte '/' && buf[i-1] != byte ' ')
			break;
	mem.name = string buf[Oname:i];
	mem.date = intof(buf[Odate: Odate+Ldate], 10);
	mem.uid = intof(buf[Ouid: Ouid+Luid], 10);
	mem.gid = intof(buf[Ogid: Ogid+Lgid], 10);
	mem.mode = intof(buf[Omode: Omode+Lmode], 8);
	mem.size = intof(buf[Osize: Osize+Lsize], 10);
	if(buf[Ofmag] != ARFMAG0 || buf[Ofmag+1] != ARFMAG1)
		phaseerr(b.offset()-big SAR_HDR);
	return mem;
}

intof(a: array of byte, base: int): int
{
	for(i := len a; i > 0; i--)
		if(a[i-1] != byte ' '){
			a = a[0:i];
			break;
		}
	(n, s) := str->toint(string a, base);
	if(s != nil){
		sys->fprint(stderr, "ar: invalid integer in archive member's header: %q\n", string a);
		raise "fail:error";
	}
	return n;
}

Armember.wrhdr(mem: self ref Armember, fd: ref Sys->FD)
{
	b := array[SAR_HDR] of {* => byte ' '};
	nm := array of byte mem.name;
	if(len nm > Lname)
		nm = nm[0:Lname];
	b[Oname:] = nm;
	b[Odate:] = sys->aprint("%-12ud", mem.date);
	b[Ouid:] = sys->aprint("%-6d", 0);
	b[Ogid:] = sys->aprint("%-6d", 0);
	b[Omode:] = sys->aprint("%-8uo", mem.mode);
	b[Osize:] = sys->aprint("%-10ud", mem.size);
	b[Ofmag] = ARFMAG0;
	b[Ofmag+1] = ARFMAG1;
	mustwrite(fd, b, len b);
}

#
# make a new member from the given file, with the file's contents
#
Armember.new(name: string, fd: ref Sys->FD): ref Armember
{
	mem := ref Armember;
	mem.replace(name, fd);
	return mem;
}

#
# replace the contents  of an existing member
#
Armember.replace(mem: self ref Armember, name: string, fd: ref Sys->FD)
{
	(ok, d) := sys->fstat(fd);
	if(ok < 0){
		sys->fprint(stderr, "ar: cannot stat %s: %r\n", name);
		raise "fail:no stat";
	}
	mem.name = trim(name);
	mem.date = d.mtime;
	mem.uid = 0;
	mem.gid = 0;
	mem.mode = d.mode & 8r777;
	mem.size = int d.length;
	if(big mem.size != d.length){
		sys->fprint(stderr, "ar: file %s too big\n", name);
		raise "fail:error";
	}
	mem.fd = fd;
	mem.contents = nil;	# will be copied across from fd when needed
}

#
# read the contents of an archive member
#
Armember.read(mem: self ref Armember, b: ref Iobuf): int
{
	if(mem.contents != nil)
		return len mem.contents;
	mem.contents = buffer(mem.size + (mem.size&1));
	n := b.read(mem.contents, len mem.contents);
	if(n != len mem.contents){
		if(n >= 0)
			sys->werrstr("unexpected end-of-file");
		rderr();
	}
	return n;
}

mustwrite(fd: ref Sys->FD, buf: array of byte, n: int)
{
	if(sys->write(fd, buf, n) != n)
		wrerr();
}

#
# write an archive member to ofd, including header
#
Armember.write(mem: self ref Armember, ofd: ref Sys->FD)
{
	mem.wrhdr(ofd);
	if(mem.contents != nil){
		mustwrite(ofd, mem.contents, len mem.contents);
		return;
	}
	if(mem.fd == nil)
		raise "ar: write nil fd";
	buf := array[Sys->ATOMICIO] of byte;	# could be bigger
	for(nr := mem.size; nr > 0;){
		n := nr;
		if(n > len buf)
			n = len buf;
		n = sys->read(mem.fd, buf, n);
		if(n <= 0){
			if(n == 0)
				sys->werrstr("unexpected end-of-file");
			rderr();
		}
		mustwrite(ofd, buf, n);
		nr -= n;
	}
	if(mem.size & 1)
		mustwrite(ofd, array[] of {byte '\n'}, 1);
}

#
# seek past the current member's contents in b
#
Armember.skip(mem: self ref Armember, b: ref Iobuf)
{
	b.seek(big(mem.size + (mem.size&1)), 1);
}

#
# copy a member's contents from memory or directly from an archive to another file
#
Armember.copyout(mem: self ref Armember, b: ref Iobuf, ofd: ref Sys->FD)
{
	if(mem.contents != nil){
		mustwrite(ofd, mem.contents, len mem.contents);
		return;
	}
	buf := array[Sys->ATOMICIO] of byte;	# could be bigger
	for(nr := mem.size; nr > 0;){
		n := nr;
		if(n > len buf)
			n = len buf;
		n = b.read(buf, n);
		if(n <= 0){
			if(n == 0)
				sys->werrstr("unexpected end-of-file");
			rderr();
		}
		mustwrite(ofd, buf, n);
		nr -= n;
	}
	if(mem.size & 1)
		b.getc();
}

#
# 	Temp file I/O subsystem.  We attempt to cache all three temp files in
# 	core.  When we run out of memory we spill to disk.
# 	The I/O model assumes that temp files:
# 		1) are only written on the end
# 		2) are only read from the beginning
# 		3) are only read after all writing is complete.
# 	The architecture uses one control block per temp file.  Each control
# 	block anchors a chain of buffers, each containing an archive contents.
#
Arfile.new(): ref Arfile
{
	return ref Arfile;
}

#
# copy the contents of mem at b into the temporary
#
Arfile.copy(ap: self ref Arfile, b: ref Iobuf, mem: ref Armember)
{
	mem.read(b);
	ap.insert(mem);
}

#
#  insert a contents buffer into the contents chain
#
Arfile.insert(ap: self ref Arfile, mem: ref Armember)
{
	mem.next = nil;
	if(ap.head == nil)
		ap.head = mem;
	else
		ap.tail.next = mem;
	ap.tail = mem;
}

#
# stream the contents in a temp file to the file referenced by 'fd'.
#
Arfile.stream(ap: self ref Arfile, fd: ref Sys->FD)
{
	if(ap.fd != nil){		# copy prefix from disk
		buf := array[Sys->ATOMICIO] of byte;
		sys->seek(ap.fd, big 0, 0);
		while((n := sys->read(ap.fd, buf, len buf)) > 0)
			mustwrite(fd, buf, n);
		if(n < 0)
			rderr();
		ap.fd = nil;
	}
	# dump the in-core buffers, which always follow the contents in the temp file
	for(mem := ap.head; mem != nil; mem = mem.next)
		mem.write(fd);
}

#
# spill a member's contents to disk
#

totalmem := 0;
warned := 0;
tn := 0;

Arfile.page(ap: self ref Arfile): int
{
	mem := ap.head;
	if(ap.fd == nil && !warned){
		pid := sys->pctl(0, nil);
		for(i := 0;; i++){
			name := sys->sprint("/tmp/art%d.%d.%d", pid, tn, i);
			ap.fd = sys->create(name, Sys->OEXCL | Sys->ORDWR | Sys->ORCLOSE, 8r600);
			if(ap.fd != nil)
				break;
			if(i >= 20){
				warned =1;
				sys->fprint(stderr,"ar: warning: can't create temp file %s: %r\n", name);
				return 0;	# we'll simply use the memory
			}
		}
		tn++;
	}
	mem.write(ap.fd);
	ap.head = mem.next;
	if(ap.tail == mem)
		ap.tail = mem.next;
	totalmem -= len mem.contents;
	return 1;
}

#
# account for the space taken by a contents's contents,
# pushing earlier contentss to disk to keep the space below a
# reasonable level
#

buffer(n: int): array of byte
{
Flush:
	while(totalmem + n > 1024*1024){
		for(i := 0; i < len parts; i++)
			if(parts[i] != nil && parts[i].page())
				continue Flush;
		break;
	}
	totalmem += n;
	return array[n] of byte;
}
