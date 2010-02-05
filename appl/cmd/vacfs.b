implement Vacfs;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "string.m";
include "daytime.m";
include "venti.m";
include "vac.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";

str: String;
daytime: Daytime;
venti: Venti;
vac: Vac;
styxservers: Styxservers;

print, sprint, fprint, fildes: import sys;
Score, Session: import venti;
Roottype, Dirtype, Pointertype0, Datatype: import venti;
Root, Entry, Direntry, Metablock, Metaentry, Entrysize, Modeperm, Modeappend, Modeexcl, Modedir, Modesnapshot, Vacdir, Vacfile, Source: import vac;
Styxserver, Fid, Navigator, Navop, Enotfound: import styxservers;

Vacfs: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := pflag := 0;
session: ref Session;

ss: ref Styxserver;

Elem: adt {
	qid:	int;
	de: 	ref Direntry;
	size:	big;
	pick {
	File =>	vf: 	ref Vacfile;
	Dir =>	vd:	ref Vacdir;
		pqid:	int;
		offset:	int;
		nprev:	int;
		prev:	array of ref Sys->Dir;
	}

	new:	fn(nqid: int, vd: ref Vacdir, de: ref Direntry, pqid: int): ref Elem;
	stat:	fn(e: self ref Elem): ref Sys->Dir;
};

Qdir: adt {
	qid:	int;
	cqids:	list of (string, int); # name, qid
};

elems := array[512] of list of ref Elem;
qids := array[512] of list of ref Qdir;
lastqid := 0;
qidscores: list of (string, int);


childget(qid: int, name: string): ref Elem
{
	for(l := qids[qid % len qids]; l != nil; l = tl l) {
		if((hd l).qid != qid)
			continue;
		for(m := (hd l).cqids; m != nil; m = tl m) {
			(cname, cq) := hd m;
			if(name == cname)
				return get(cq);
		}
	}
	return nil;
}

childput(qid: int, name: string): int
{
	qd: ref Qdir;
	for(l := qids[qid % len qids]; l != nil; l = tl l)
		if((hd l).qid == qid) {
			qd = hd l;
			break;
		}
	if(qd == nil) {
		qd = ref Qdir(qid, nil);
		qids[qid % len qids] = qd::nil;
	}
	qd.cqids = (name, ++lastqid)::qd.cqids;
	return lastqid;
}

scoreget(score: string): ref Elem
{
	for(l := qidscores; l != nil; l = tl l) {
		(s, n) := hd l;
		if(s == score)
			return get(n);
	}
	return nil;
}

scoreput(score: string): int
{
	qidscores = (score, ++lastqid)::qidscores;
	return lastqid;
}


Elem.new(nqid: int, vd: ref Vacdir, de: ref Direntry, pqid: int): ref Elem
{
	(e, me) := vd.open(de);
	if(e == nil)
		return nil;
	if(de.mode & Vac->Modedir)
		return ref Elem.Dir(nqid, de, e.size, Vacdir.new(session, e, me), pqid, 0, 0, nil);
	return ref Elem.File(nqid, de, e.size, Vacfile.new(session, e));
}

Elem.stat(e: self ref Elem): ref Sys->Dir
{
	d := e.de.mkdir();
	d.qid.path = big e.qid;
	d.length = e.size;
	return d;
}

walk(ed: ref Elem.Dir, name: string): (ref Elem, string)
{
	if(name == "..")
		return (get(ed.pqid), nil);

	if(ed.qid == 0) {
		ne := scoreget(name);
		if(ne == nil) {
			(ok, score) := Score.parse(name);
			if(ok != 0)
				return (nil, "bad score: "+name);

			(vd, de, err) := vac->vdroot(session, score);
			if(err != nil)
				return (nil, err);

			nqid := scoreput(name);
			ne = ref Elem.Dir(nqid, de, big 0, vd, ed.qid, 0, 0, nil);
			set(ne);
		}
		return (ne, nil);
	}

	de := ed.vd.walk(name);
	if(de == nil)
		return (nil, sprint("%r"));
	ne := childget(ed.qid, de.elem);
	if(ne == nil) {
		nqid := childput(ed.qid, de.elem);
		ne = Elem.new(nqid, ed.vd, de, ed.qid);
		if(ne == nil)
			return (nil, sprint("%r"));
		set(ne);
	}
	return (ne, nil);
}

get(qid: int): ref Elem
{
	for(l := elems[qid % len elems]; l != nil; l = tl l)
		if((hd l).qid == qid)
			return hd l;
	return nil;
}

set(e: ref Elem)
{
	elems[e.qid % len elems] = e::elems[e.qid % len elems];
}

getfile(qid: int): ref Elem.File
{
	pick file := get(qid) {
	File =>	return file;
	}
	error("internal error, getfile");
	return nil;
}

getdir(qid: int): ref Elem.Dir
{
	pick d := get(qid) {
	Dir =>	return d;
	}
	error("internal error, getdir");
	return nil;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	daytime = load Daytime Daytime->PATH;
	venti = load Venti Venti->PATH;
	styx = load Styx Styx->PATH;
	styxservers = load Styxservers Styxservers->PATH;
	vac = load Vac Vac->PATH;
	venti->init();
	vac->init();
	styx->init();
	styxservers->init(styx);

	sys->pctl(sys->NEWPGRP, nil);
	if(venti == nil || vac == nil)
		error("loading venti,vac");

	arg->init(args);
	arg->setusage(arg->progname()+" [-Ddp] [-a addr] [[tag:]score]");
	while((ch := arg->opt()) != 0)
		case ch {
		'D' =>	styxservers->traceset(1);
		'a' =>	addr = arg->earg();
		'd' =>	dflag++;
			vac->dflag++;
		'p' =>	pflag++;
		* =>	warn(sprint("bad option: -%c", ch));
			arg->usage();
		}
	args = arg->argv();
	if(len args > 1)
		arg->usage();

	score: ref Score;
	if(len args == 1) {
		(tag, scorestr) := str->splitstrr(hd args, ":");
		if(tag != nil)
			tag = tag[:len tag-1];
		if(tag == nil)
			tag = "vac";
		if(tag != "vac")
			error("bad score type: "+tag);
		(ok, s) := Score.parse(scorestr);
		if(ok != 0)
			error("bad score: "+scorestr);
		score = ref s;
	}

	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		error(sprint("dialing %s: %r", addr));
	say("have connection");

	fd := conn.dfd;
	session = Session.new(fd);
	if(session == nil)
		error(sprint("handshake: %r"));
	say("have handshake");

	rqid := 0;
	red: ref Elem;
	if(args == nil) {
		de := Direntry.new();
		de.uid = de.gid = de.mid = user();
		de.ctime = de.atime = de.mtime = daytime->now();
		de.mode = Vac->Modedir|8r755;
		de.emode = Sys->DMDIR|8r755;
		red = ref Elem.Dir(rqid, de, big 0, nil, rqid, 0, 0, nil);
	} else {
		(vd, de, err) := vac->vdroot(session, *score);
		if(err != nil)
			error(err);
		rqid = ++lastqid;
		red = ref Elem.Dir(rqid, de, big 0, vd, rqid, 0, 0, nil);
	}
	set(red);
	say(sprint("have root, qid=%d", rqid));

	navchan := chan of ref Navop;
	nav := Navigator.new(navchan);
	spawn navigator(navchan);

	msgc: chan of ref Tmsg;
	(msgc, ss) = Styxserver.new(sys->fildes(0), nav, big rqid);

	for(;;) {
		pick m := <- msgc {
		Readerror =>
			say("read error: "+m.error);

		Read =>
			say(sprint("have read, offset=%ubd count=%d", m.offset, m.count));
			(c, err) := ss.canread(m);
			if(c == nil){
				ss.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			if(c.qtype & Sys->QTDIR){
				ss.default(m);
				break;
			}

			ef := getfile(int c.path);
			n := m.count;
			a := array[n] of byte;
			have := ef.vf.pread(a, n, m.offset);
			if(have < 0) {
				ss.reply(ref Rmsg.Error(m.tag, sprint("%r")));
				break;
			}
			ss.reply(ref Rmsg.Read(m.tag, a[:have]));

		Open =>
			(c, mode, f, err) := canopen(m);
			if(c == nil){
				ss.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			c.open(mode, f.qid);
			ss.reply(ref Rmsg.Open(m.tag, f.qid, ss.iounit()));


		* =>
			ss.default(m);
		}
	}
}

canopen(m: ref Tmsg.Open): (ref Fid, int, ref Sys->Dir, string)
{
	c := ss.getfid(m.fid);
	if(c == nil)
		return (nil, 0, nil, Styxservers->Ebadfid);
	if(c.isopen)
		return (nil, 0, nil, Styxservers->Eopen);
	(f, err) := ss.t.stat(c.path);
	if(f == nil)
		return (nil, 0, nil, err);
	mode := styxservers->openmode(m.mode);
	if(mode == -1)
		return (nil, 0, nil, Styxservers->Ebadarg);
	if(mode != Sys->OREAD && f.qid.qtype & Sys->QTDIR)
		return (nil, 0, nil, Styxservers->Eperm);
	if(!pflag && !styxservers->openok(c.uname, m.mode, f.mode, f.uid, f.gid))
		return (nil, 0, nil, Styxservers->Eperm);
	if(m.mode & Sys->ORCLOSE)
		return (nil, 0, nil, Styxservers->Eperm);
	return (c, mode, f, err);
}

navigator(c: chan of ref Navop)
{
loop:
	for(;;) {
		navop := <- c;
		say(sprint("have navop, path=%bd", navop.path));
		pick n := navop {
		Stat =>
			say(sprint("have stat"));
			n.reply <-= (get(int n.path).stat(), nil);

		Walk =>
			say(sprint("have walk, name=%q", n.name));
			ed := getdir(int n.path);
			(ne, err) := walk(ed, n.name);
			if(err != nil) {
				n.reply <-= (nil, err);
				break;
			}
			n.reply <-= (ne.stat(), nil);

		Readdir =>
			say(sprint("have readdir path=%bd offset=%d count=%d", n.path, n.offset, n.count));
			if(n.path == big 0) {
				n.reply <-= (nil, nil);
				break;
			}
			ed := getdir(int n.path);
			if(n.offset == 0) {
				ed.vd.rewind();
				ed.offset = 0;
				ed.nprev = 0;
				ed.prev = array[0] of ref Sys->Dir;
			}
			skip := n.offset-ed.offset;
			if(skip > 0) {
				ed.prev = ed.prev[skip:];
				ed.nprev -= skip;
				ed.offset += skip;
			}
			if(len ed.prev < n.count) {
				newprev := array[n.count] of ref Sys->Dir;
				newprev[:] = ed.prev;
				ed.prev = newprev;
			}
			while(ed.nprev < n.count) {
				(ok, de) := ed.vd.readdir();
				if(ok < 0) {
					say(sprint("readdir error: %r"));
					n.reply <-= (nil, sprint("reading directory: %r"));
					continue loop;
				}
				if(de == nil)
					break;
				ne := childget(ed.qid, de.elem);
				if(ne == nil) {
					nqid := childput(ed.qid, de.elem);
					ne = Elem.new(nqid, ed.vd, de, ed.qid);
					if(ne == nil) {
						n.reply <-= (nil, sprint("%r"));
						continue loop;
					}
					set(ne);
				}
				d := ne.stat();
				ed.prev[ed.nprev++] = d;
				n.reply <-= (d, nil);
			}
			n.reply <-= (nil, nil);
		}
	}
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
	killgrp();
	fprint(fildes(2), "%s\n", s);
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

killgrp()
{
	fd := sys->open("/prog/"+string sys->pctl(0, nil)+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp\n");
}
