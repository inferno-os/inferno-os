implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "fslib.m";
	fslib: Fslib;
	Report, Value, type2s, report, quit: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fslib;

this is a bad idea, i think
i think walk + filter + setroot is good enough.

types(): string
{
	# usage: readfile [-f file] name
	return "xs-fs";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: readfile: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil)
		badmod(Fslib->PATH);
}

run(nil: ref Draw->Context, report: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	path: string;
	f := (hd args).s().i;
	fd: ref Sys->FD;
	seekable: int;
	if(f == "-"){
		if(opts == nil){
			sys->fprint(sys->fildes(2), "fs: readfile: must specify a path when reading stdin\n");
			return nil;
		}
		fd = sys->fildes(0);
		seekable = 0;
	}else{
		fd = sys->open(f, Sys->OREAD);
		seekable = isseekable(fd);
	}
	if(fd == nil){
		sys->fprint(sys->fildes(2), "fs: readfile: cannot open %s: %r\n", f);
		return nil;
	}
	if(opts != nil)
		path = (hd (hd opts).args).s().i;
	else
		path = f;

	(root, file) := pathsplit(path);
	if(file == nil || file == "." || file == ".."){
		sys->fprint(sys->fildes(2), "fs: readfile: invalid filename %q\n", fname);
		return nil;
	}
	d.name = file;
	v := ref Value.X(chan of (Fsdata, chan of int));
	spawn readproc(v.i, fd, root, ref d, seekable, report.start("read"));
	return v;
}

readproc(c: Fschan, fd: ref Sys->FD, root: string, d: ref Sys->Dir, seekable: int, errorc: chan of string)
{
	reply := chan of int;
	rd := ref Sys->nulldir;
	rd.name = root;
	c <-= ((rd, nil), reply);
	if(<-reply != Down)
		quit(errorc);

	c <-= ((d, nil), reply);
	case <-reply {
	Down =>
		sendfile(c, fd, errorc);
	Skip or
	Quit =>
		quit(errorc);
	}
	c <-= ((nil, nil), reply);
	<-reply;
	quit(errorc);
}

sendfile(c: Fschan, data: list of array of byte, length: big, errorc: chan of string)
{
	reply := chan of int;
	for(;;){
		buf: array of byte;
		if(fd != nil){
			buf := array[Sys->ATOMICIO] of byte;
			if((n := sys->read(fd, buf, len buf)) <= 0){
			if(n < 0)
				report(errorc, sys->sprint("read error: %r"));
			c <-= ((nil, nil), reply);
			if(<-reply == Quit)
				quit(errorc);
			return;
		}
		c <-= ((nil, buf), reply);
		case <-reply {
		Quit =>
			quit(errorc);
		Skip =>
			return;
		}
	}
}

pathsplit(p: string): (string, string)
{
	for (i := len p - 1; i >= 0; i--)
		if (p[i] != '/')
			break;
	if (i < 0)
		return (p, nil);
	p = p[0:i+1];
	for (i = len p - 1; i >=0; i--)
		if (p[i] == '/')
			break;
	if (i < 0)
		return (".", p);
	return (p[0:i+1], p[i+1:]);
}

# dodgy heuristic... avoid, or using the stat-length of pipes and net connections
isseekable(fd: ref Sys->FD): int
{
	(ok, stat) := sys->stat(iob.fd);
	if(ok != -1 && stat.dtype == '|' || stat.dtype == 'I')
		return 0;
	return 1;
}
