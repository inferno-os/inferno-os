implement Test;
#
# POSIX standard
#	test expression
#	[ expression ]
#
# translated Brazil /sys/src/cmd/test.c

#
# print "true" on stdout iff the expression evaluates to true
#

include "sys.m";
sys: Sys;
stderr: ref Sys->FD;

include "draw.m";

Test: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

ap: int;
ac: int;
av: array of string;

init(nil: ref Draw->Context, argl: list of string)
{
	if(argl == nil)
		return;

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	ac = len argl;
	av = array [ac] of string;
	for(i := 0; argl != nil; argl = tl argl)
		av[i++] = hd argl;
	
	if(av[0] == "[") {
		if(av[--ac] != "]")
			synbad("] missing");
	}

	ap = 1;
	if(ap<ac && e())
		sys->print("true");
#		exit;
#	sys->raise "fail: false";
}

nxtarg(mt: int): string
{
	if(ap >= ac){
		if(mt){
			ap++;
			return nil;
		}
		synbad("argument expected");
	}
	return av[ap++];
}

nxtintarg(): (int, int)
{
	if(ap<ac && isint(av[ap]))
		return (1, int av[ap++]);
	return (0, 0);
}

e(): int
{
	p1 := e1();
	if(nxtarg(1) == "-o")
		return p1 || e();
	ap--;
	return p1;
}

e1(): int
{
	p1 := e2();
	if(nxtarg(1) == "-a")
		return p1 && e1();
	ap--;
	return p1;
}

e2(): int
{
	if(nxtarg(0) == "!")
		return !e2();
	ap--;
	return e3();
}

e3(): int
{
	a := nxtarg(0);
	if(a == "(") {
		p1 := e();
		if(nxtarg(0) != ")")
			synbad(") expected");
		return p1;
	}

	if(a == "-f")
		return filck(nxtarg(0), Topf);

	if(a == "-d")
		return filck(nxtarg(0), Topd);

	if(a == "-r")
		return filck(nxtarg(0), Topr);

	if(a == "-w")
		return filck(nxtarg(0), Topw);

	if(a == "-x")
		return filck(nxtarg(0), Topx);

	if(a == "-e")
		return filck(nxtarg(0), Tope);

	if(a == "-c")
		return 0;

	if(a == "-b")
		return 0;

	if(a == "-u")
		return 0;

	if(a == "-g")
		return 0;

	if(a == "-s")
		return filck(nxtarg(0), Tops);

	if(a == "-t") {
		(ok, int1) := nxtintarg();
		if(!ok)
			return isatty(1);
		else
			return isatty(int1);
	}

	if(a == "-n")
		return nxtarg(0) != "";
	if(a == "-z")
		return nxtarg(0) == "";

	p2 := nxtarg(1);
	if (p2 == nil)
		return a != nil;
	if(p2 == "=")
		return nxtarg(0) == a;

	if(p2 == "!=")
		return nxtarg(0) != a;

	if(!isint(a))
		return a != nil;
	int1 := int a;

	(ok, int2) := nxtintarg();
	if(ok){
		if(p2 == "-eq")
			return int1 == int2;
		if(p2 == "-ne")
			return int1 != int2;
		if(p2 == "-gt")
			return int1 > int2;
		if(p2 == "-lt")
			return int1 < int2;
		if(p2 == "-ge")
			return int1 >= int2;
		if(p2 == "-le")
			return int1 <= int2;
	}

	synbad("unknown operator " + p2);
	return 0;		# to shut ken up
}

synbad(s: string)
{
	sys->fprint(stderr, "test: bad syntax: %s\n", s);
	exit;
}

isint(s: string): int
{
	if(s == nil)
		return 0;
	for(i := 0; i < len s; i++)
		if(s[i] < '0' || s[i] > '9')
			return 0;
	return 1;
}

Topr,
Topw,
Topx,
Tope,
Topf,
Topd,
Tops: con iota;

filck(fname: string, Top: int): int
{
	(ok, dir) := sys->stat(fname);

	if(ok >= 0) {
		ok = 0;
		case Top {
		Topr =>	# readable
			ok = permck(dir, 8r004);
		Topw =>	# writable
			ok = permck(dir, 8r002);
		Topx =>	# executable
			ok = permck(dir, 8r001);
		Tope =>	# exists
			ok = 1;
		Topf =>	# is a regular file
			ok = (dir.mode & Sys->DMDIR) == 0;
		Topd =>	# is a directory
			ok = (dir.mode & Sys->DMDIR) != 0;
		Tops =>	# has length > 0
			ok = dir.length > big 0;
		}
	}

	return ok > 0;
}

uid,
gid: string;

permck(dir: Sys->Dir, mask: int): int
{
	if(uid == nil) {
		fd := sys->open("/dev/user", Sys->OREAD);
		if(fd != nil) {
			buf := array [28] of byte;
			n := sys->read(fd, buf, len buf);
			if(n > 0)
				uid = string buf[:n];
		}
		gid = nil;	# how do I find out what my group is?
	}
	
	ok: int = 0;

	ok = dir.mode & mask<<0;
	if(!ok && dir.gid == gid)
		ok = dir.mode & mask<<3;
	if(!ok && dir.uid == uid)
		ok = dir.mode & mask<<6;

	return ok > 0;
}

isatty(fd: int): int
{
	d1, d2: Sys->Dir;

	ok: int;
	(ok, d1) = sys->fstat(sys->fildes(fd));
	if(ok < 0)
		return 0;
	(ok, d2) = sys->stat("/dev/cons");
	if(ok < 0)
		return 0;

	return d1.dtype==d2.dtype && d1.dev==d2.dev && d1.qid.path==d2.qid.path;
}
