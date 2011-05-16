implement Vacput;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
include "daytime.m";
	dt: Daytime;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "dial.m";
	dial: Dial;
include "string.m";
	str: String;
include "tables.m";
	tables: Tables;
	Strhash: import tables;
include "venti.m";
	venti: Venti;
	Root, Entry, Score, Session: import venti;
include "vac.m";
	vac: Vac;
	Direntry, File, Sink, MSink: import vac;

Vacput: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "$venti";
dflag: int;
iflag: int;
vflag: int;
xflag: int;
blocksize := vac->Dsize;
uid: string;
gid: string;

pathgen: big;

bout: ref Iobuf;
session: ref Session;
name := "vac";
itab,
xtab: ref Strhash[string]; # include/exclude paths

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	dt = load Daytime Daytime->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;
	dial = load Dial Dial->PATH;
	str = load String String->PATH;
	tables = load Tables Tables->PATH;
	venti = load Venti Venti->PATH;
	vac = load Vac Vac->PATH;
	if(venti == nil || vac == nil)
		fail("loading venti,vac");
	venti->init();
	vac->init();

	arg->init(args);
	arg->setusage(arg->progname()+" [-dv] [-i | -x] [-a addr] [-b blocksize] [-n name] [-u uid] [-g gid] path ...");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'b' =>	blocksize = int arg->earg();
		'n' =>	name = arg->earg();
		'd' =>	vac->dflag = dflag++;
		'i' =>	iflag++;
		'v' =>	vflag++;
		'x' =>	xflag++;
		'g' =>	gid = arg->earg();
		'u' =>	uid = arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args == 0)
		arg->usage();
	if(iflag && xflag) {
		warn("cannot have both -i and -x");
		arg->usage();
	}

	if(vflag)
		bout = bufio->fopen(sys->fildes(1), bufio->OWRITE);

	if(iflag || xflag) {
		t := readpaths();
		if(iflag)
			itab = t;
		else
			xtab = t;
	}

	addr = dial->netmkaddr(addr, "net", "venti");
	cc := dial->dial(addr, nil);
	if(cc == nil)
		fail(sprint("dialing %s: %r", addr));
	say("have connection");

	fd := cc.dfd;
	session = Session.new(fd);
	if(session == nil)
		fail(sprint("handshake: %r"));
	say("have handshake");

	topde: ref Direntry;
	if(len args == 1 && ((nil, d) := sys->stat(hd args)).t0 == 0 && (d.mode&Sys->DMDIR)) {
		topde = Direntry.mk(d);
		topde.elem = name;
	} else {
		topde = Direntry.new();
		topde.elem = name;
		topde.uid = topde.gid = user();
		topde.mode = 8r777|Vac->Modedir;
		topde.mtime = topde.atime = 0;
	}
	topde.qid = pathgen++;
	if(uid != nil)
		topde.uid = uid;
	if(gid != nil)
		topde.gid = gid;
	topde.ctime = dt->now();

	s := Sink.new(session, blocksize);
	ms := MSink.new(session, blocksize);
	for(; args != nil; args = tl args)
		writepath(hd args, s, ms);
	say("tree written");

	if(vflag && bout.flush() == bufio->ERROR)
		fail(sprint("write stdout: %r"));

	e0 := s.finish();
	if(e0 == nil)
		fail(sprint("writing top entry: %r"));
	e1 := ms.finish();
	if(e1 == nil)
		fail(sprint("writing top meta entry: %r"));
	topde.qidspace = 1;
	topde.qidoff = big 0;
	topde.qidmax = pathgen;
	s2 := MSink.new(session, blocksize);
	if(s2.add(topde) < 0)
		fail(sprint("adding direntry for top entries: %r"));
	e2 := s2.finish();
	say("top meta entry written, "+e2.score.text());

 	td := array[venti->Entrysize*3] of byte;
 	td[0*venti->Entrysize:] = e0.pack();
 	td[1*venti->Entrysize:] = e1.pack();
 	td[2*venti->Entrysize:] = e2.pack();
	(tok, tscore) := session.write(venti->Dirtype, td);
	if(tok < 0)
		fail(sprint("writing top-level entries: %r"));

	root := ref Root(venti->Rootversion, name, "vac", tscore, blocksize, nil);
	rd := root.pack();
	if(rd == nil)
		fail(sprint("root pack: %r"));
	(rok, rscore) := session.write(venti->Roottype, rd);
	if(rok < 0)
		fail(sprint("writing root score: %r"));
	sys->print("vac:%s\n", rscore.text());
	if(session.sync() < 0)
		fail(sprint("syncing server: %r"));
}

readpaths(): ref Strhash[string]
{
	t := Strhash[string].new(199, nil);
	b := bufio->fopen(sys->fildes(0), bufio->OREAD);
	if(b == nil)
		fail(sprint("fopen: %r"));
	for(;;) {
		s := b.gets('\n');
		if(s == nil)
			break;
		if(s[len s-1] == '\n')
			s = s[:len s-1];
		t.add(s, s);
	}
	return t;
}

usepath(p: string): int
{
	if(itab != nil)
		return itab.find(p) != nil;
	if(xtab != nil)
		return xtab.find(p) == nil;
	return 1;
}

writepath(path: string, s: ref Sink, ms: ref MSink)
{
	if(!usepath(path))
		return;

	if(vflag && bout.puts(path+"\n") == bufio->ERROR)
		fail(sprint("write stdout: %r"));

	fd := sys->open(path, sys->OREAD);
	if(fd == nil)
		fail(sprint("opening %s: %r", path));
	(ok, dir) := sys->fstat(fd);
	if(ok < 0)
		fail(sprint("fstat %s: %r", path));
	if(dir.mode&sys->DMAUTH)
		return warn(path+": is auth file, skipping");
	if(dir.mode&sys->DMTMP)
		return warn(path+": is temporary file, skipping");

	e, me: ref Entry;
	de: ref Direntry;
	qid := pathgen++;
	if(dir.mode & sys->DMDIR) {
		ns := Sink.new(session, blocksize);
		nms := MSink.new(session, blocksize);
		for(;;) {
			(n, dirs) := sys->dirread(fd);
			if(n == 0)
				break;
			if(n < 0)
				fail(sprint("dirread %s: %r", path));
			for(i := 0; i < len dirs; i++) {
				d := dirs[i];
				npath := path+"/"+d.name;
				writepath(npath, ns, nms);
			}
		}
		e = ns.finish();
		if(e == nil)
			fail(sprint("error flushing dirsink for %s: %r", path));
		me = nms.finish();
		if(me == nil)
			fail(sprint("error flushing metasink for %s: %r", path));
	} else {
		e = writefile(path, fd);
		if(e == nil)
			fail(sprint("error flushing filesink for %s: %r", path));
	}

	case dir.name {
	"/" =>	dir.name = "root";
	"." =>	dir.name = "dot";
	}
	de = Direntry.mk(dir);
	de.qid = qid;
	if(uid != nil)
		de.uid = uid;
	if(gid != nil)
		de.gid = gid;

	i := s.add(e);
	if(i < 0)
		fail(sprint("adding entry to sink: %r"));
	mi := 0;
	if(me != nil)
		mi = s.add(me);
	if(mi < 0)
		fail(sprint("adding mentry to sink: %r"));
	de.entry = i;
	de.mentry = mi;
	i = ms.add(de);
	if(i < 0)
		fail(sprint("adding direntry to msink: %r"));
}

writefile(path: string, fd: ref Sys->FD): ref Entry
{
	bio := bufio->fopen(fd, bufio->OREAD);
	if(bio == nil)
		fail(sprint("bufio opening %s: %r", path));

	f := File.new(session, venti->Datatype, blocksize);
	for(;;) {
		buf := array[blocksize] of byte;
		n := 0;
		while(n < len buf) {
			want := len buf - n;
			have := bio.read(buf[n:], want);
			if(have == 0)
				break;
			if(have < 0)
				fail(sprint("reading %s: %r", path));
			n += have;
		}

		if(f.write(buf[:n]) < 0)
			fail(sprint("writing %s: %r", path));
		if(n != len buf)
			break;
	}
	bio.close();
	return f.finish();
}

user(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd != nil)
	if((n := sys->read(fd, d := array[128] of byte, len d)) > 0)
		return string d[:n];
	return "nobody";
}

fd2: ref Sys->FD;
warn(s: string)
{
	if(fd2 == nil)
		fd2 = sys->fildes(2);
	sys->fprint(fd2, "%s\n", s);
}

say(s: string)
{
	if(dflag)
		warn(s);
}

fail(s: string)
{
	warn(s);
	raise "fail:"+s;
}
