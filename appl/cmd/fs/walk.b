implement Fsmodule;
include "sys.m";
	sys: Sys;
include "readdir.m";
	readdir: Readdir;
include "draw.m";
include "sh.m";
include "fslib.m";
	fslib: Fslib;
	Report, Value, type2s, report, quit: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fslib;

Loopcheck: adt {
	a: array of list of ref Sys->Dir;

	new:		fn(): ref Loopcheck;
	enter:	fn(l: self ref Loopcheck, d: ref Sys->Dir): int;
	leave:	fn(l: self ref Loopcheck, d: ref Sys->Dir);
};

types(): string
{
	return "xs-bs";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: walk: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil)
		badmod(Fslib->PATH);
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		badmod(Readdir->PATH);
}

run(nil: ref Draw->Context, report: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	path := (hd args).s().i;
	(ok, d) := sys->stat(path);
	if(ok== -1){
		sys->fprint(sys->fildes(2), "fs: walk: cannot stat %q: %r\n", path);
		return nil;
	}
	if((d.mode & Sys->DMDIR) == 0){
		# XXX could produce an fs containing just the single file.
		# would have to split the path though.
		sys->fprint(sys->fildes(2), "fs: walk: %q is not a directory\n", path);
		return nil;
	}
	sync := chan of int;
	c := chan of (Fsdata, chan of int);
	spawn fswalkproc(sync, path, c, Sys->ATOMICIO, report.start("walk"));
	<-sync;
	return ref Value.X(c);
}

# XXX need to avoid loops in the filesystem...
fswalkproc(sync: chan of int, path: string, c: Fschan, blocksize: int, errorc: chan of string)
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	# XXX could allow a single root file?
	if(sys->chdir(path) == -1){
		report(errorc, sys->sprint("cannot cd to %q: %r", path));
		fslib->sendnulldir(c);
		quit(errorc);
	}
	(ok, d) := sys->stat(".");
	if(ok == -1){
		report(errorc, sys->sprint("cannot stat %q: %r", path));
		fslib->sendnulldir(c);
		quit(errorc);
	}
	d.name = path;
	reply := chan of int;
	c <-= ((ref d, nil), reply);
	if(<-reply == Down){
		loopcheck := Loopcheck.new();
		loopcheck.enter(ref d);
		if(path[len path - 1] != '/')
			path[len path] = '/';
		fswalkdir(path, c, blocksize, loopcheck, errorc);
		c <-= ((nil, nil), reply);
		<-reply;
	}
	quit(errorc);
}

fswalkdir(path: string, c: Fschan, blocksize: int, loopcheck: ref Loopcheck, errorc: chan of string)
{
	reply := chan of int;
	(a, n) := readdir->init(".", Readdir->NAME|Readdir->COMPACT);
	if(n == -1){
		report(errorc, sys->sprint("cannot readdir %q: %r", path));
		return;
	}
	for(i := 0; i < n; i++)
		if(a[i].mode & Sys->DMDIR)
			if(loopcheck.enter(a[i]) == 0)
				a[i].dtype = ~0;
directory:
	for(i = 0; i < n; i++){
		if(a[i].mode & Sys->DMDIR){
			d := a[i];
			if(d.dtype == ~0){
				report(errorc, sys->sprint("filesystem loop at %#q", path + d.name));
				continue;
			}
			if(sys->chdir("./" + d.name) == -1){
				report(errorc, sys->sprint("cannot cd to %#q: %r", path + a[i].name));
				continue;
			}
			c <-= ((d, nil), reply);
			case <-reply {
			Quit =>
				quit(errorc);
			Down =>
				fswalkdir(path + a[i].name + "/", c, blocksize, loopcheck, errorc);
				c <-= ((nil, nil), reply);
				if(<-reply == Quit)
					quit(errorc);
			Skip =>
				sys->chdir("..");
				i++;
				break directory;
			Next =>
				break;
			}
			if(sys->chdir("..") == -1)		# XXX what should we do if this fails?
				report(errorc, sys->sprint("failed to cd .. from %#q: %r\n", path + a[i].name));
			
		} else {
			if(fswalkfile(path, a[i], c, blocksize, errorc) == Skip)
				break directory;
		}
	}
	for(i = n - 1; i >= 0; i--)
		if(a[i].mode & Sys->DMDIR && a[i].dtype != ~0)
			loopcheck.leave(a[i]);
}

fswalkfile(path: string, d: ref Sys->Dir, c: Fschan, blocksize: int, errorc: chan of string): int
{
	reply := chan of int;
	fd := sys->open(d.name, Sys->OREAD);
	if(fd == nil){
		report(errorc, sys->sprint("cannot open %q: %r", path+d.name));
		return Next;
	}
	c <-= ((d, nil), reply);
	case <-reply {
	Quit =>
		quit(errorc);
	Skip =>
		return Skip;
	Next =>
		return Next;
	Down =>
		break;
	}
	length := d.length;
	for(n := big 0; n < length; ){
		nr := blocksize;
		if(n + big blocksize > length)
			nr = int (length - n);
		buf := array[nr] of byte;
		nr = sys->read(fd, buf, nr);
		if(nr <= 0){
			if(nr < 0)
				report(errorc, sys->sprint("error reading %q: %r", path + d.name));
			else
				report(errorc, sys->sprint("%q is shorter than expected (%bd/%bd)",
						path + d.name, n, length));
			break;
		}else if(nr < len buf)
			buf = buf[0:nr];
		c <-= ((nil, buf), reply);
		case <-reply {
		Quit =>
			quit(errorc);
		Skip =>
			return Next;
		}
		n += big nr;
	}
	c <-= ((nil, nil), reply);
	if(<-reply == Quit)
		quit(errorc);
	return Next;
}

HASHSIZE: con 32;

issamedir(d0, d1: ref Sys->Dir): int
{
	(q0, q1) := (d0.qid, d1.qid);
	return q0.path == q1.path &&
		q0.qtype == q1.qtype &&
		d0.dtype == d1.dtype &&
		d0.dev == d1.dev;
}

Loopcheck.new(): ref Loopcheck
{
	return ref Loopcheck(array[HASHSIZE] of list of ref Sys->Dir);
}

# XXX we're assuming no-one modifies the values in d behind our back...
Loopcheck.enter(l: self ref Loopcheck, d: ref Sys->Dir): int
{
	slot := int d.qid.path & (HASHSIZE-1);
	for(ll := l.a[slot]; ll != nil; ll = tl ll)
		if(issamedir(d, hd ll))
			return 0;
	l.a[slot] = d :: l.a[slot];
	return 1;
}

Loopcheck.leave(l: self ref Loopcheck, d: ref Sys->Dir)
{
	slot := int d.qid.path & (HASHSIZE-1);
	l.a[slot] = tl l.a[slot];
}
