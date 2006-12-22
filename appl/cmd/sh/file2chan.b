implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "lock.m";
	lock: Lock;
	Semaphore: import lock;
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;

Tag: adt {
	tagid, blocked: int;
	offset, fid: int;
	pick {
	Read =>
		count: int;
		rc: chan of (array of byte, string);
	Write =>
		data: array of byte;
		wc: chan of (int, string);
	}
};

taglock: ref Lock->Semaphore;
maxtagid := 1;
tags := array[16] of list of ref Tag;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;

	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("file2chan: cannot load self: %r"));

	lock = load Lock Lock->PATH;
	if (lock == nil) ctxt.fail("bad module", sys->sprint("file2chan: cannot load %s: %r", Lock->PATH));
	lock->init();

	taglock = Semaphore.new();
	if (taglock == nil)
		ctxt.fail("no lock", "file2chan: cannot make lock");


	ctxt.addbuiltin("file2chan", myself);
	ctxt.addbuiltin("rblock", myself);
	ctxt.addbuiltin("rread", myself);
	ctxt.addbuiltin("rreadone", myself);
	ctxt.addbuiltin("rwrite", myself);
	ctxt.addbuiltin("rerror", myself);
	ctxt.addbuiltin("fetchwdata", myself);
	ctxt.addbuiltin("putrdata", myself);
	ctxt.addsbuiltin("rget", myself);

	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

runbuiltin(ctxt: ref Context, nil: Sh,
			cmd: list of ref Listnode, nil: int): string
{
	case (hd cmd).word {
	"file2chan" =>		return builtin_file2chan(ctxt, cmd);
	"rblock" =>		return builtin_rblock(ctxt, cmd);
	"rread" =>			return builtin_rread(ctxt, cmd, 0);
	"rreadone" =>		return builtin_rread(ctxt, cmd, 1);
	"rwrite" =>		return builtin_rwrite(ctxt, cmd);
	"rerror" =>		return builtin_rerror(ctxt, cmd);
	"fetchwdata" =>	return builtin_fetchwdata(ctxt, cmd);
	"putrdata" =>		return builtin_putrdata(ctxt, cmd);
	}
	return nil;
}

runsbuiltin(ctxt: ref Context, nil: Sh,
			argv: list of ref Listnode): list of ref Listnode
{
	# could add ${rtags} to retrieve list of currently outstanding tags
	case (hd argv).word {
	"rget" =>			return sbuiltin_rget(ctxt, argv);
	}
	return nil;
}

builtin_file2chan(ctxt: ref Context, argv: list of ref Listnode): string
{
	rcmd, wcmd, ccmd: ref Listnode;
	path: string;

	n := len argv;
	if (n < 4 || n > 5)
		ctxt.fail("usage", "usage: file2chan file {readcmd} {writecmd} [ {closecmd} ]");

	(path, argv) = ((hd tl argv).word, tl tl argv);
	(rcmd, argv) = (hd argv, tl argv);
	(wcmd, argv) = (hd argv, tl argv);
	if (argv != nil)
		ccmd = hd argv;
	if (path == nil || !iscmd(rcmd) || !iscmd(wcmd) || (ccmd != nil && !iscmd(ccmd)))
		ctxt.fail("usage", "usage: file2chan file {readcmd} {writecmd} [ {closecmd} ]");

	(dir, f) := pathsplit(path);
	if (sys->bind("#s", dir, Sys->MBEFORE|Sys->MCREATE) == -1) {
		reporterror(ctxt, sys->sprint("file2chan: cannot bind #s: %r"));
		return "no #s";
	}
	fio := sys->file2chan(dir, f);
	if (fio == nil) {
		reporterror(ctxt, sys->sprint("file2chan: cannot make %s: %r", path));
		return "cannot make chan";
	}
	sync := chan of int;
	spawn srv(sync, ctxt, fio, rcmd, wcmd, ccmd);
	apid := <-sync;
	ctxt.set("apid", ref Listnode(nil, string apid) :: nil);
	if (ctxt.options() & ctxt.INTERACTIVE)
		sys->fprint(sys->fildes(2), "%d\n", apid);
	return nil;
}

srv(sync: chan of int, ctxt: ref Context,
		fio: ref Sys->FileIO, rcmd, wcmd, ccmd: ref Listnode)
{
	ctxt = ctxt.copy(1);
	sync <-= sys->pctl(0, nil);
	for (;;) {
		fid, offset, count: int;
		rc: Sys->Rread;
		wc: Sys->Rwrite;
		d: array of byte;
		t: ref Tag = nil;
		cmd: ref Listnode = nil;
		alt {
		(offset, count, fid, rc) = <-fio.read =>
			if (rc != nil) {
				t = ref Tag.Read(0, 0, offset, fid, count, rc);
				cmd = rcmd;
			} else
				continue;		# we get a close on both read and write...
		(offset, d, fid, wc) = <-fio.write =>
			if (wc != nil) {
				t = ref Tag.Write(0, 0, offset, fid, d, wc);
				cmd = wcmd;
			}
		}
		if (t != nil) {
			addtag(t);
			ctxt.setlocal("tag", ref Listnode(nil, string t.tagid) :: nil);
			ctxt.run(cmd :: nil, 0);
			taglock.obtain();
			# make a default reply if it hasn't been deliberately blocked.
			del := 0;
			if (t.tagid >= 0 && !t.blocked) {
				pick mt := t {
				Read =>
					rreply(mt.rc, nil, "invalid read");
				Write =>
					wreply(mt.wc, len mt.data, nil);
				}
				del = 1;
			}
			taglock.release();
			if (del)
				deltag(t.tagid);
			ctxt.setlocal("tag", nil);
		} else if (ccmd != nil) {
			t = ref Tag.Read(0, 0, -1, fid, -1, nil);
			addtag(t);
			ctxt.setlocal("tag", ref Listnode(nil, string t.tagid) :: nil);
			ctxt.run(ccmd :: nil, 0);
			deltag(t.tagid);
			ctxt.setlocal("tag", nil);
		}
	}
}

builtin_rread(ctxt: ref Context, argv: list of ref Listnode, one: int): string
{
	n := len argv;
	if (n < 2 || n > 3)
		ctxt.fail("usage", "usage: "+(hd argv).word+" [tag] data");
	argv = tl argv;

	t := envgettag(ctxt, argv, n == 3);
	if (t == nil)
		ctxt.fail("bad tag", "rread: cannot find tag");
	if (n == 3)
		argv = tl argv;
	mt := etr(ctxt, "rread", t);
	arg := word(hd argv);
	d := array of byte arg;
	if (one) {
		if (mt.offset >= len d)
			d = nil;
		else
			d = d[mt.offset:];
	}
	if (len d > mt.count)
		d = d[0:mt.count];
	rreply(mt.rc, d, nil);
	deltag(t.tagid);
	return nil;
}

builtin_rwrite(ctxt: ref Context, argv: list of ref Listnode): string
{
	n := len argv;
	if (n > 3)
		ctxt.fail("usage", "usage: rwrite [tag [count]]");
	t := envgettag(ctxt, tl argv, n > 1);
	if (t == nil)
		ctxt.fail("bad tag", "rwrite: cannot find tag");

	mt := etw(ctxt, "rwrite", t);
	count := len mt.data;
	if (n == 3) {
		arg := word(hd tl argv);
		if (!isnum(arg))
			ctxt.fail("usage", "usage: freply [tag [count]]");
		count = int arg;
	}
	wreply(mt.wc, count, nil);
	deltag(t.tagid);
	return nil;
}

builtin_rblock(ctxt: ref Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if (len argv > 1)
		ctxt.fail("usage", "usage: rblock [tag]");
	t := envgettag(ctxt, argv, argv != nil);
	if (t == nil)
		ctxt.fail("bad tag", "rblock: cannot find tag");
	t.blocked = 1;
	return nil;
}

sbuiltin_rget(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	n := len argv;
	if (n < 2 || n > 3)
		ctxt.fail("usage", "usage: rget (data|count|offset|fid) [tag]");
	argv = tl argv;
	t := envgettag(ctxt, tl argv, tl argv != nil);
	if (t == nil)
		ctxt.fail("bad tag", "rget: cannot find tag");
	s := "";
	case (hd argv).word {
	"data" =>
		s = string etw(ctxt, "rget", t).data;
	"count" =>
		s = string etr(ctxt, "rget", t).count;
	"offset" =>
		s = string t.offset;
	"fid" =>
		s = string t.fid;
	* =>
		ctxt.fail("usage", "usage: rget (data|count|offset|fid) [tag]");
	}

	return ref Listnode(nil, s) :: nil;
}

builtin_fetchwdata(ctxt: ref Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if (len argv > 1)
		ctxt.fail("usage", "usage: fetchwdata [tag]");
	t := envgettag(ctxt, argv, argv != nil);
	if (t == nil)
		ctxt.fail("bad tag", "fetchwdata: cannot find tag");
	d := etw(ctxt, "fetchwdata", t).data;
	sys->write(sys->fildes(1), d, len d);
	return nil;
}

builtin_putrdata(ctxt: ref Context, argv: list of ref Listnode): string
{
	argv = tl argv;
	if (len argv > 1)
		ctxt.fail("usage", "usage: putrdata [tag]");
	t := envgettag(ctxt, argv, argv != nil);
	if (t == nil)
		ctxt.fail("bad tag", "putrdata: cannot find tag");
	mt := etr(ctxt, "putrdata", t);
	buf := array[mt.count] of byte;
	n := 0;
	fd := sys->fildes(0);
	while (n < mt.count) {
		nr := sys->read(fd, buf[n:mt.count], mt.count - n);
		if (nr <= 0)
			break;
		n += nr;
	}

	rreply(mt.rc, buf[0:n], nil);
	deltag(t.tagid);
	return nil;
}

builtin_rerror(ctxt: ref Context, argv: list of ref Listnode): string
{
	# usage: ferror [tag] error
	n := len argv;
	if (n < 2 || n > 3)
		ctxt.fail("usage", "usage: ferror [tag] error");
	t := envgettag(ctxt, tl argv, n == 3);
	if (t == nil)
		ctxt.fail("bad tag", "rerror: cannot find tag");
	if (n == 3)
		argv = tl argv;
	err := word(hd tl argv);
	pick mt := t {
	Read =>
		rreply(mt.rc, nil, err);
	Write =>
		wreply(mt.wc, 0, err);
	}
	deltag(t.tagid);
	return nil;
}

envgettag(ctxt: ref Context, args: list of ref Listnode, useargs: int): ref Tag
{
	tagid: int;
	if (useargs)
		tagid = int (hd args).word;
	else {
		args = ctxt.get("tag");
		if (args == nil || tl args != nil)
			return nil;
		tagid = int (hd args).word;
	}
	return gettag(tagid);
}

etw(ctxt: ref Context, cmd: string, t: ref Tag): ref Tag.Write
{
	pick mt := t {
	Write =>	return mt;
	}
	ctxt.fail("bad tag", cmd + ": inappropriate tag id");
	return nil;
}

etr(ctxt: ref Context, cmd: string, t: ref Tag): ref Tag.Read
{
	pick mt := t {
	Read =>	return mt;
	}
	ctxt.fail("bad tag", cmd + ": inappropriate tag id");
	return nil;
}

wreply(wc: chan of (int, string), count: int, err: string)
{
	alt {
	wc <-= (count, err) => ;
	* => ;
	}
}

rreply(rc: chan of (array of byte, string), d: array of byte, err: string)
{
	alt {
	rc <-= (d, err) => ;
	* => ;
	}
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}

isnum(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] > '9' || s[i] < '0')
			return 0;
	return 1;
}

iscmd(n: ref Listnode): int
{
	return n.cmd != nil || (n.word != nil && n.word[0] == '}');
}

addtag(t: ref Tag)
{
	taglock.obtain();
	t.tagid = maxtagid++;
	slot := t.tagid % len tags;
	tags[slot] = t :: tags[slot];
	taglock.release();
}

deltag(tagid: int)
{
	taglock.obtain();
	slot := tagid % len tags;
	nwl: list of ref Tag;
	for (wl := tags[slot]; wl != nil; wl = tl wl)
		if ((hd wl).tagid != tagid)
			nwl = hd wl :: nwl;
		else
			(hd wl).tagid = -1;
	tags[slot] = nwl;
	taglock.release();
}

gettag(tagid: int): ref Tag
{
	slot := tagid % len tags;
	for (wl := tags[slot]; wl != nil; wl = tl wl)
		if ((hd wl).tagid == tagid)
			return hd wl;
	return nil;
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

reporterror(ctxt: ref Context, err: string)
{
	if (ctxt.options() & ctxt.VERBOSE)
		sys->fprint(sys->fildes(2), "%s\n", err);
}
