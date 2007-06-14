implement Vacput;

include "sys.m";
	sys: Sys;
include "draw.m";
include "daytime.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
include "string.m";
include "venti.m";
include "vac.m";

daytime: Daytime;
str: String;
venti: Venti;
vac: Vac;

print, sprint, fprint, fildes: import sys;
Score, Session: import venti;
Roottype, Dirtype, Pointertype0, Datatype: import venti;
Root, Entry, Direntry, Metablock, Metaentry, Entrysize, File, Sink, MSink: import vac;

Vacput: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := 0;
vflag := 0;
blocksize := vac->Dsize;
session: ref Session;
name := "vac";

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	daytime = load Daytime Daytime->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	venti = load Venti Venti->PATH;
	vac = load Vac Vac->PATH;
	if(venti == nil || vac == nil)
		error("loading venti,vac");
	venti->init();
	vac->init();

	arg->init(args);
	arg->setusage(sprint("%s [-dtv] [-a addr] [-b blocksize] [-n name] path ...", arg->progname()));
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'b' =>	blocksize = int arg->earg();
		'n' =>	name = arg->earg();
		'd' =>	dflag++;
			vac->dflag++;
		'v' =>	vflag++;
		* =>	warn(sprint("bad option: -%c", c));
			arg->usage();
		}
	args = arg->argv();
	if(len args == 0)
		arg->usage();

	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		error(sprint("dialing %s: %r", addr));
	say("have connection");

	fd := conn.dfd;
	session = Session.new(fd);
	if(session == nil)
		error(sprint("handshake: %r"));
	say("have handshake");

	topde: ref Direntry;
	if(len args == 1 && ((nil, d) := sys->stat(hd args)).t0 == 0 && d.mode&Sys->DMDIR) {
		topde = Direntry.mk(d);
		topde.elem = name;
	} else {
		topde = Direntry.new();
		topde.elem = name;
		topde.uid = topde.gid = user();
		topde.mode = 8r777|Vac->Modedir;
		topde.mtime = topde.atime = 0;
	}
	topde.ctime = daytime->now();

	s := Sink.new(session, blocksize);
	ms := MSink.new(session, blocksize);
	for(; args != nil; args = tl args)
		writepath(hd args, s, ms);
	say("tree written");

	e0 := s.finish();
	if(e0 == nil)
		error(sprint("writing top entry: %r"));
	e1 := ms.finish();
	if(e1 == nil)
		error(sprint("writing top meta entry: %r"));
	say(sprint("top entries written (%s, %s)", e0.score.text(), e1.score.text()));
	s2 := MSink.new(session, blocksize);
	if(s2.add(topde) < 0)
		error(sprint("adding direntry for top entries: %r"));
	e2 := s2.finish();
	say("top meta entry written, "+e2.score.text());

 	td := array[Entrysize*3] of byte;
 	td[0*Entrysize:] = e0.pack();
 	td[1*Entrysize:] = e1.pack();
 	td[2*Entrysize:] = e2.pack();
	(tok, tscore) := session.write(Dirtype, td);
	if(tok < 0)
		error(sprint("writing top-level entries: %r"));
	say("top entry written, "+tscore.text());

	root := Root.new(name, "vac", tscore, blocksize, nil);
	rd := root.pack();
	if(rd == nil)
		error(sprint("root pack: %r"));
	(rok, rscore) := session.write(Roottype, rd);
	if(rok < 0)
		error(sprint("writing root score: %r"));
	say("root written, "+rscore.text());
	print("vac:%s\n", rscore.text());
	if(session.sync() < 0)
		error(sprint("syncing server: %r"));
}

writepath(path: string, s: ref Sink, ms: ref MSink)
{
	if(vflag)
		print("%s\n", path);
say("writepath "+path);
	fd := sys->open(path, sys->OREAD);
	if(fd == nil)
		error(sprint("opening %s: %r", path));
	(ok, dir) := sys->fstat(fd);
	if(ok < 0)
		error(sprint("fstat %s: %r", path));
say("writepath: file opened");
	if(dir.mode&sys->DMAUTH) {
		warn(path+": is auth file, skipping");
		return;
	}
	if(dir.mode&sys->DMTMP) {
		warn(path+": is temporary file, skipping");
		return;
	}

	e, me: ref Entry;
	de: ref Direntry;
	if(dir.mode & sys->DMDIR) {
say("writepath: file is dir");
		ns := Sink.new(session, blocksize);
		nms := MSink.new(session, blocksize);
		for(;;) {
			(n, dirs) := sys->dirread(fd);
			if(n == 0)
				break;
			if(n < 0)
				error(sprint("dirread %s: %r", path));
			for(i := 0; i < len dirs; i++) {
				d := dirs[i];
				npath := path+"/"+d.name;
				writepath(npath, ns, nms);
			}
		}
		e = ns.finish();
		if(e == nil)
			error(sprint("error flushing dirsink for %s: %r", path));
		me = nms.finish();
		if(me == nil)
			error(sprint("error flushing metasink for %s: %r", path));
	} else {
say("writepath: file is normale file");
		e = writefile(path, fd);
		if(e == nil)
			error(sprint("error flushing filesink for %s: %r", path));
	}
say("writepath: wrote path, "+e.score.text());

	de = Direntry.mk(dir);
say("writepath: have direntry");

	i := s.add(e);
	if(i < 0)
		error(sprint("adding entry to sink: %r"));
	mi := 0;
	if(me != nil)
		mi = s.add(me);
	if(mi < 0)
		error(sprint("adding mentry to sink: %r"));
	de.entry = i;
	de.mentry = mi;
	i = ms.add(de);
	if(i < 0)
		error(sprint("adding direntry to msink: %r"));
say("writepath done");
}

writefile(path: string, fd: ref Sys->FD): ref Entry
{
	bio := bufio->fopen(fd, bufio->OREAD);
	if(bio == nil)
		error(sprint("bufio opening %s: %r", path));
	say(sprint("bufio opened path %s", path));

	f := File.new(session, Datatype, blocksize);
	for(;;) {
		buf := array[blocksize] of byte;
		n := 0;
		while(n < len buf) {
			want := len buf - n;
			have := bio.read(buf[n:], want);
			if(have == 0)
				break;
			if(have < 0)
				error(sprint("reading %s: %r", path));
			n += have;
		}
		say(sprint("have buf, length %d", n));

		if(f.write(buf[:n]) < 0)
			error(sprint("writing %s: %r", path));
		if(n != len buf)
			break;
	}
	bio.close();
	return f.finish();
}

user(): string
{
	if((fd := sys->open("/dev/user", Sys->OREAD)) != nil
		&& (n := sys->read(fd, d := array[128] of byte, len d)) > 0)
		return string d[:n];
	return "nobody";
}

error(s: string)
{
	warn(s);
	raise "fail:"+s;
}

warn(s: string)
{
	fprint(fildes(2), "%s\n", s);
}

say(s: string)
{
	if(dflag)
		warn(s);
}
