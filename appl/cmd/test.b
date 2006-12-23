implement Test;

#
#	venerable
#		test expression
#

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;

include "draw.m";

include "daytime.m";
	daytime: Daytime;

Test: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

gargs: list of string;

init(nil: ref Draw->Context, args: list of string)
{
	if(args == nil)
		return;
	gargs = tl args;

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	if(gargs == nil)
		raise "fail:usage";
	if(!e())
		raise "fail:false";
}

nextarg(mt: int): string
{
	if(gargs == nil){
		if(mt)
			return nil;
		synbad("argument expected");
	}
	s := hd gargs;
	gargs = tl gargs;
	return s;
}

nextintarg(): (int, int)
{
	if(gargs != nil && isint(hd gargs))
		return (1, int nextarg(0));
	return (0, 0);
}

isnextarg(s: string): int
{
	if(gargs != nil && hd gargs == s){
		gargs = tl gargs;
		return 1;
	}
	return 0;
}

e(): int
{
	p1 := e1();
	if(isnextarg("-o"))
		return p1 || e();
	return p1;
}

e1(): int
{
	p1 := e2();
	if(isnextarg("-a"))
		return p1 && e1();
	return p1;
}

e2(): int
{
	if(isnextarg("!"))
		return !e2();
	return e3();
}

e3(): int
{
	a := nextarg(0);
	case a {
	"(" =>
		p1 := e();
		if(nextarg(0) != ")")
			synbad(") expected");
		return p1;
	"-A" =>
		return hasmode(nextarg(0), Sys->DMAPPEND);
	"-L" =>
		return hasmode(nextarg(0), Sys->DMEXCL);
	"-T" =>
		return hasmode(nextarg(0), Sys->DMTMP);
	"-f" =>
		f := nextarg(0);
		return exists(f) && !hasmode(f, Sys->DMDIR);
	"-d" =>
		return hasmode(nextarg(0), Sys->DMDIR);
	"-r" =>
		return sys->open(nextarg(0), Sys->OREAD) != nil;
	"-w" =>
		return sys->open(nextarg(0), Sys->OWRITE) != nil;
	"-x" =>
		fd := sys->open(nextarg(0), Sys->OREAD);
		if(fd == nil)
			return 0;
		(ok, d) := sys->fstat(fd);
		if(ok < 0)
			return 0;
		return (d.mode & 8r111) != 0;
	"-e" =>
		return exists(nextarg(0));
	"-s" =>
		(ok, d) := sys->stat(nextarg(0));
		if(ok < 0)
			return 0;
		return d.length > big 0;
	"-t" =>
		(ok, fd) := nextintarg();
		if(!ok)
			return iscons(1);
		return iscons(fd);
	"-n" =>
		return nextarg(0) != "";
	"-z" =>
		return nextarg(0) == "";
	* =>
		p2 := nextarg(1);
		if(p2 == nil)
			return a != nil;
		case p2 {
		"=" =>
			return nextarg(0) == a;
		"!=" =>
			return nextarg(0) != a;
		"-older" =>
			return isolder(nextarg(0), a);
		"-ot" =>
			return isolderthan(a, nextarg(0));
		"-nt" =>
			return isnewerthan(a, nextarg(0));
		}

		if(!isint(a))
			return a != nil;

		int1 := int a;
		(ok, int2) := nextintarg();
		if(ok){
			case p2 {
			"-eq" =>
				return int1 == int2;
			"-ne" =>
				return int1 != int2;
			"-gt" =>
				return int1 > int2;
			"-lt" =>
				return int1 < int2;
			"-ge" =>
				return int1 >= int2;
			"-le" =>
				return int1 <= int2;
			}
		}

		synbad("unknown operator " + p2);
		return 0;
	}
}

synbad(s: string)
{
	sys->fprint(stderr, "test: bad syntax: %s\n", s);
	raise "fail:bad syntax";
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

exists(f: string): int
{
	return sys->stat(f).t0 >= 0;
}

hasmode(f: string, m: int): int
{
	(ok, d) := sys->stat(f);
	if(ok < 0)
		return 0;
	return (d.mode & m) != 0;
}

iscons(fno: int): int
{
	fd := sys->fildes(fno);
	if(fd == nil)
		return 0;
	s := sys->fd2path(fd);
	n := len "/dev/cons";
	return s == "#c/cons" || len s >= n && s[len s-n:] == "/dev/cons";
}

isolder(t: string, f: string): int
{
	(ok, dir) := sys->stat(f);
	if(ok < 0)
		return 0;

	n := 0;
	for(i := 0; i < len t;){
		for(j := i; j < len t; j++)
			if(!(t[j] >= '0' && t[j] <= '9'))
				break;
		if(i == j)
			synbad("bad time syntax, "+t);
		m := int t[i:j];
		i = j;
		if(i == len t){
			n = m;
			break;
		}
		case t[i++] {
		'y' =>	n += m*12*30*24*3600;
		'M' =>	n += m*30*24*3600;
		'd' =>	n += m*24*3600;
		'h' =>	n += m*3600;
		'm' =>	n += m*60;
		's' =>		n += m;
		* =>		synbad("bad time syntax, "+t);
		}
	}

	return dir.mtime+n < now();
}

isolderthan(a: string, b: string): int
{
	(aok, ad) := sys->stat(a);
	if(aok < 0)
		return 0;
	(bok, bd) := sys->stat(b);
	if(bok < 0)
		return 0;
	return ad.mtime < bd.mtime;
}

isnewerthan(a: string, b: string): int
{
	(aok, ad) := sys->stat(a);
	if(aok < 0)
		return 0;
	(bok, bd) := sys->stat(b);
	if(bok < 0)
		return 0;
	return ad.mtime > bd.mtime;
}

now(): int
{
	if(daytime == nil){
		daytime = load Daytime Daytime->PATH;
		if(daytime == nil)
			synbad(sys->sprint("can't load %s: %r", Daytime->PATH));
	}
	return daytime->now();
}
