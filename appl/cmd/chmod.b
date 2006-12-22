implement Chmod;

include "sys.m";
include "draw.m";
include "string.m";

Chmod: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

sys:	Sys;
stderr: ref Sys->FD;

str:	String;

User:	con 8r700;
Group:	con 8r070;
Other:	con 8r007;
All:	con User | Group | Other;

Read:	con 8r444;
Write:	con 8r222;
Exec:	con 8r111;

usage()
{
	sys->fprint(stderr, "usage: chmod [8r]777 file ... or chmod [augo][+-=][rwxal] file ...\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	str = load String String->PATH;
	if(str == nil){
		sys->fprint(stderr, "chmod: cannot load %s: %r\n", String->PATH);
		raise "fail:bad module";
	}

	if(len argv < 3)
		usage();
	argv = tl argv;
	m := hd argv;
	argv = tl argv;

	mask := All;
	if (str->prefix("8r", m))
		m = m[2:];
	(mode, s) := str->toint(m, 8);
	if(s != "" || m == ""){
		ok := 0;
		(ok, mask, mode) = parsemode(m);
		if(!ok){
			sys->fprint(stderr, "chmod: bad mode '%s'\n", m);
			usage();
		}
	}
	ndir := sys->nulldir;
	for(; argv != nil; argv = tl argv){
		f := hd argv;
		(ok, dir) := sys->stat(f);
		if(ok < 0){
			sys->fprint(stderr, "chmod: cannot stat %s: %r\n", f);
			continue;
		}
		ndir.mode = (dir.mode & ~mask) | (mode & mask);
		if(sys->wstat(f, ndir) < 0)
			sys->fprint(stderr, "chmod: cannot wstat %s: %r\n", f);
	}
}

parsemode(spec: string): (int, int, int)
{
	mask := Sys->DMAPPEND | Sys->DMEXCL | Sys->DMTMP;
loop:	for(i := 0; i < len spec; i++){
		case spec[i] {
		'u' =>
			mask |= User;
		'g' =>
			mask |= Group;
		'o' =>
			mask |= Other;
		'a' =>
			mask |= All;
		* =>
			break loop;
		}
	}
	if(i == len spec)
		return (0, 0, 0);
	if(i == 0)
		mask |= All;

	op := spec[i++];
	if(op != '+' && op != '-' && op != '=')
		return (0, 0, 0);

	mode := 0;
	for(; i < len spec; i++){
		case spec[i]{
		'r' =>
			mode |= Read;
		'w' =>
			mode |= Write;
		'x' =>
			mode |= Exec;
		'a' =>
			mode |= Sys->DMAPPEND;
		'l' =>
			mode |= Sys->DMEXCL;
		't' =>
			mode |= Sys->DMTMP;
		* =>
			return (0, 0, 0);
		}
	}
	if(op == '+' || op == '-')
		mask &= mode;
	if(op == '-')
		mode = ~mode;
	return (1, mask, mode);
}
