implement Lockfs;
include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxlib.m";
	styxlib: Styxlib;
	Dirtab, Styxserver, Chan,
	devdir,
	Eperm, Ebadfid, Eexists, Enotdir, Enotfound, Einuse: import styxlib;
include "arg.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	auth: Auth;
include "dial.m";
	dial: Dial;

Lockfs: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
	dirgen: fn(srv: ref Styxlib->Styxserver, c: ref Styxlib->Chan,
			tab: array of Styxlib->Dirtab, i: int): (int, Sys->Dir);
};

Elocked: con "file is locked";

devgen: Dirgenmod;

Openreq: adt {
	srv: ref Styxserver;
	tag: int;
	omode: int;
	c: ref Chan;
	uproc: Uproc;
};

Lockqueue: adt {
	h: list of ref Openreq; 
	t: list of ref Openreq;
	put: fn(q: self ref Lockqueue, s: ref Openreq);
	get: fn(q: self ref Lockqueue): ref Openreq;
	peek: fn(q: self ref Lockqueue): ref Openreq;
	flush: fn(q: self ref Lockqueue, srv: ref Styxserver, tag: int);
};

Lockfile: adt {
	waitq: ref Lockqueue;
	fd: ref Sys->FD;
	readers: int;
	writers: int;
	d: Sys->Dir;
};

Ureq: adt {
	fname: string;
	pick {
	Open =>
		omode: int;
	Create =>
		omode: int;
		perm: int;
	Remove =>
	Wstat =>
		dir: Sys->Dir;
	}
};

Uproc: type chan of (ref Ureq, chan of (ref Sys->FD, string));

maxqidpath := big 1;
locks: list of ref Lockfile;
lockdir: string;
authinfo: ref Keyring->Authinfo;
timefd: ref Sys->FD;

MAXCONN: con 20;

verbose := 0;

usage()
{
	sys->fprint(stderr, "usage: lockfs [-A] [-a alg]... [-p addr] dir [mountpoint]\n");
	raise "fail:usage";
}

badmodule(p: string)
{
	sys->fprint(stderr, "lockfs: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	styx = load Styx Styx->PATH;
	if (styx == nil)
		badmodule(Styx->PATH);
	dial = load Dial Dial->PATH;
	if (dial == nil)
		badmodule(Dial->PATH);
	styx->init();
	styxlib = load Styxlib Styxlib->PATH;
	if (styxlib == nil)
		badmodule(Styxlib->PATH);
	styxlib->init(styx);
	devgen = load Dirgenmod "$self";
	if (devgen == nil)
		badmodule("self as Dirgenmod");
	timefd = sys->open("/dev/time", sys->OREAD);
	if (timefd == nil) {
		sys->fprint(stderr, "lockfs: cannot open /dev/time: %r\n");
		raise "fail:no time";
	}
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);
	arg->init(argv);

	addr := "";
	doauth := 1;
	algs: list of string;
	while ((opt := arg->opt()) != 0) {
		case opt {
		'p' =>
			addr = arg->arg();
		'a' =>
			alg := arg->arg();
			if (alg == nil)
				usage();
			algs = alg :: algs;
		'A' =>
			doauth = 0;
		'v' =>
			verbose = 1;
		* =>
			usage();
		}
	}
	argv = arg->argv();
	if (argv == nil || (addr != nil && tl argv != nil))
		usage();
	if (addr == nil)
		doauth = 0;		# no authentication necessary for local mount
	if (doauth) {
		auth = load Auth Auth->PATH;
		if (auth == nil)
			badmodule(Auth->PATH);
		if ((e := auth->init()) != nil) {
			sys->fprint(stderr, "lockfs: cannot init auth: %s\n", e);
			raise "fail:errors";
		}
		keyring = load Keyring Keyring->PATH;
		if (keyring == nil)
			badmodule(Keyring->PATH);
		authinfo = keyring->readauthinfo("/usr/" + user() + "/keyring/default");
	}

	mountpoint := lockdir = hd argv;
	if (tl argv != nil)
		mountpoint = hd tl argv;
	if (addr != nil) {
		if (doauth && algs == nil)
			algs = "none" :: nil;		# XXX is this default a bad idea?
		srvrq := chan of (ref Sys->FD, string, Uproc);
		srvsync := chan of (int, string);
		spawn listener(addr, srvrq, srvsync, algs);
		(srvpid, err) := <-srvsync;
		srvsync = nil;
		if (srvpid == -1) {
			sys->fprint(stderr, "lockfs: failed to start listener: %s\n", err);
			raise "fail:errors";
		}
		sync := chan of int;
		spawn server(srvrq, sync);
		<-sync;
	} else {
		rq := chan of (ref Sys->FD, string, Uproc);
		fds := array[2] of ref Sys->FD;
		sys->pipe(fds);
		sync := chan of int;
		spawn server(rq, sync);
		<-sync;
		rq <-= (fds[0], "lock", nil);
		rq <-= (nil, nil, nil);
		if (sys->mount(fds[1], nil, mountpoint, Sys->MREPL | Sys->MCREATE, nil) == -1) {
			sys->fprint(stderr, "lockfs: cannot mount: %r\n");
			raise "fail:cannot mount";
		}
	}
}

server(srvrq: chan of (ref Sys->FD, string, Uproc), sync: chan of int)
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	down := 0;
	nclient := 0;
	tchans := array[MAXCONN] of chan of ref Tmsg;
	srv := array[MAXCONN] of ref Styxserver;
	uprocs := array[MAXCONN] of Uproc;
	lockinit();
Service:
	for (;;) alt {
	(fd, reqstr, uprocch) := <-srvrq =>
		if (fd == nil) {
			if (verbose && reqstr != nil)
				sys->print("lockfs: localserver going down (reason: %s)\n", reqstr);
			down = 1;
		} else {
			if (verbose)
				sys->print("lockfs: got new connection (s == '%s')\n", reqstr);
			for (i := 0; i < len tchans; i++)
				if (tchans[i] == nil) {
					(tchans[i], srv[i]) = Styxserver.new(fd);
					if(verbose)
						sys->print("svc started\n");
					uprocs[i] = uprocch;
					break;
				}
			if (i == len tchans) {
				sys->fprint(stderr, "lockfs: too many clients\n");	# XXX expand arrays
				if (uprocch != nil)
					uprocch <-= (nil, nil);
			} else
				nclient++;
		}
	(n, gm) := <-tchans =>
		if (handletmsg(srv[n], gm, uprocs[n]) == -1) {
			tchans[n] = nil;
			srv[n] = nil;
			if (uprocs[n] != nil) {
				uprocs[n] <-= (nil, nil);
				uprocs[n] = nil;
			}
			if (nclient-- <= 1 && down)
				break Service;
		}
	}
	if (verbose)
		sys->print("lockfs: finished\n");
}

dirgen(nil: ref Styxserver, nil: ref Styxlib->Chan,
				nil: array of Dirtab, s: int): (int, Sys->Dir)
{
	d: Sys->Dir;
	ll := locks;
	for (i := 0; i < s && ll != nil; i++)
		ll = tl ll;
	if (ll == nil)
		return (-1, d);
	return (1, (hd ll).d);
}
		
handletmsg(srv:  ref Styxserver, gm: ref Tmsg, uproc: Uproc): int
{
{
	if (gm == nil)
		gm = ref Tmsg.Readerror(-1, "eof");
	if(verbose)
		sys->print("<- %s\n", gm.text());
	pick m := gm {
	Readerror =>
		# could be more efficient...
		for (cl := srv.chanlist(); cl != nil; cl = tl cl) {
			c := hd cl;
			for (ll := locks; ll != nil; ll = tl ll) {
				if ((hd ll).d.qid.path == c.qid.path) {
					l := hd ll;
					l.waitq.flush(srv, -1);
					if (c.open)
						unlocked(l);
					break;
				}
			}
		}
		if (m.error != "eof")
			sys->fprint(stderr, "lockfs: read error: %s\n", m.error);
		return -1;
	Version =>
		srv.devversion(m);
	Auth =>
		srv.devauth(m);
	Walk =>
		c := fid2chan(srv, m.fid);
		qids: array of Sys->Qid;
		cc := ref *c;
		if (len m.names > 0) {
			qids = array[1] of Sys->Qid;	# it's just one level
			if ((cc.qid.qtype & Sys->QTDIR) == 0) {
				srv.reply(ref Rmsg.Error(m.tag, Enotdir));
				break;
			}
			for (ll := locks; ll != nil; ll = tl ll)
				if ((hd ll).d.name == m.names[0])
					break;
			if (ll == nil) {
				srv.reply(ref Rmsg.Error(m.tag, Enotfound));
				break;
			}
			d := (hd ll).d;
			cc.qid = d.qid;
			cc.path = d.name;
			qids[0] = c.qid;
		}
		if(m.newfid != m.fid){
			nc := srv.clone(cc, m.newfid);
			if(nc == nil){
				srv.reply(ref Rmsg.Error(m.tag, Einuse));
				break;
			}
		}else{
			c.qid = cc.qid;
			c.path = cc.path;
		}
		srv.reply(ref Rmsg.Walk(m.tag, qids));
	Open =>
		c := fid2chan(srv, m.fid);
		if (c.qid.qtype & Sys->QTDIR) {
			srv.reply(ref Rmsg.Open(m.tag, c.qid, Styx->MAXFDATA));
			break;
		}
		for (ll := locks; ll != nil; ll = tl ll)
			if ((hd ll).d.qid.path == c.qid.path)
				break;
		if (ll == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		l := hd ll;
		req := ref Openreq(srv, m.tag, m.mode, c, uproc);
		if (l.fd == nil || (m.mode == Sys->OREAD && l.writers == 0)) {
			openlockfile(l, req);
		} else {
			l.waitq.put(req);
		}
		req = nil;
	Create =>
		c := fid2chan(srv, m.fid);
		if ((c.qid.qtype & Sys->QTDIR) == 0) {
			srv.reply(ref Rmsg.Error(m.tag, Enotdir));
			break;
		}
		if (m.perm & Sys->DMDIR) {
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			break;
		}
		for (ll := locks; ll != nil; ll = tl ll)
			if ((hd ll).d.name == m.name)
				break;
		if (ll != nil) {
			srv.reply(ref Rmsg.Error(m.tag, Eexists));
			break;
		}
		(fd, err) := create(uproc, lockdir + "/" + m.name, m.mode, m.perm);
		if (fd == nil) {
			srv.reply(ref Rmsg.Error(m.tag, err));
			break;
		}
		(ok, d) := sys->fstat(fd);
		if (ok == -1) {
			srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
			break;
		}
		l := ref Lockfile(ref Lockqueue, fd, 0, 0, d);
		l.d.qid = (maxqidpath++, 0, Sys->QTFILE);
		l.d.mtime = l.d.atime = now();
		if (m.mode == Sys->OREAD)
			l.readers = 1;
		else
			l.writers = 1;
		locks = l :: locks;
		c.qid.path = (hd locks).d.qid.path;
		c.open = 1;
		srv.reply(ref Rmsg.Create(m.tag, c.qid, Styx->MAXFDATA));
	Read =>
		c := fid2chan(srv, m.fid);
		if (c.qid.qtype & Sys->QTDIR)
			srv.devdirread(m, devgen, nil);
		else {
			l := qid2lock(c.qid);
			if (l == nil)
				srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			else {
				d := array[m.count] of byte;
				sys->seek(l.fd, m.offset, Sys->SEEKSTART);
				n := sys->read(l.fd, d, m.count);
				if (n == -1)
					srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
				else {
					srv.reply(ref Rmsg.Read(m.tag, d[0:n]));
					l.d.atime = now();
				}
			}
		}
	Write =>
		c := fid2chan(srv, m.fid);
		if (c.qid.qtype & Sys->QTDIR) {
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			break;
		}
		l := qid2lock(c.qid);
		if (l == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		sys->seek(l.fd, m.offset, Sys->SEEKSTART);
		n := sys->write(l.fd, m.data, len m.data);
		if (n == -1)
			srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
		else {
			srv.reply(ref Rmsg.Write(m.tag, n));
			nlength := m.offset + big n;
			if (nlength > l.d.length)
				l.d.length = nlength;
			l.d.mtime = now();
			l.d.qid.vers++;
		}
	Clunk =>
		c := srv.devclunk(m);
		if (c != nil && c.open && (l := qid2lock(c.qid)) != nil)
			unlocked(l);
	Flush =>
		for (ll := locks; ll != nil; ll = tl ll)
			(hd ll).waitq.flush(srv, m.tag);
		srv.reply(ref Rmsg.Flush(m.tag));
	Stat =>
		srv.devstat(m, devgen, nil);
	Remove =>
		c := fid2chan(srv, m.fid);
		srv.chanfree(c);
		if (c.qid.qtype & Sys->QTDIR) {
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			break;
		}
		l := qid2lock(c.qid);
		if (l == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		if (l.fd != nil) {
			srv.reply(ref Rmsg.Error(m.tag, Elocked));
			break;
		}
		if ((err := remove(uproc, lockdir + "/" + l.d.name)) == nil) {
			srv.reply(ref Rmsg.Error(m.tag, err));
			break;
		}
		ll: list of ref Lockfile;
		for (; locks != nil; locks = tl locks)
			if (hd locks != l)
				ll = hd locks :: ll;
		locks = ll;
		srv.reply(ref Rmsg.Remove(m.tag));
	Wstat =>
		c := fid2chan(srv, m.fid);
		if (c.qid.qtype & Sys->QTDIR) {
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			break;
		}
		l := qid2lock(c.qid);
		if (l == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			break;
		}
		if ((err := wstat(uproc, lockdir + "/" + l.d.name, m.stat)) != nil) {
			srv.reply(ref Rmsg.Error(m.tag, err));
			break;
		}
		(ok, d) := sys->stat(lockdir + "/" + m.stat.name);
		if (ok == -1) {
			srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
			break;
		}
		d.qid = l.d.qid;
		l.d = d;
		srv.reply(ref Rmsg.Wstat(m.tag));
	Attach =>
		srv.devattach(m);
	}
	return 0;
}
exception e{
	"panic:*" =>
		sys->fprint(stderr, "lockfs: %s\n", e);
		srv.reply(ref Rmsg.Error(gm.tag, e[len "panic:":]));
		return 0;
}
}

unlocked(l: ref Lockfile)
{
	if (l.readers > 0)
		l.readers--;
	else
		l.writers--;
	if (l.readers > 0)
		return;
	l.fd = nil;

	# unblock all readers at the head of the queue.
	# XXX should we queuejump other readers?
	while ((nreq := l.waitq.peek()) != nil && l.writers == 0) {
		if (nreq.omode != Sys->OREAD && l.readers > 0)
			break;
		openlockfile(l, nreq);
		l.waitq.get();
	}
}

openlockfile(l: ref Lockfile, req: ref Openreq): int
{
	err: string;
	(l.fd, err) = open(req.uproc, lockdir + "/" + l.d.name, req.omode);
	if (l.fd == nil) {
		req.srv.reply(ref Rmsg.Error(req.tag, err));
		return -1;
	}
	req.c.open = 1;
	if (req.omode & Sys->OTRUNC)
		l.d.length = big 0;
	req.srv.reply(ref Rmsg.Open(req.tag, l.d.qid, Styx->MAXFDATA));
	if (req.omode == Sys->OREAD)
		l.readers++;
	else
		l.writers++;
	return 0;
}

qid2lock(q: Sys->Qid): ref Lockfile
{
	for (ll := locks; ll != nil; ll = tl ll)
		if ((hd ll).d.qid.path == q.path)
			return hd ll;
	return nil;
}

lockinit()
{
	fd := sys->open(lockdir, Sys->OREAD);
	if (fd == nil)
		return;

	lockl: list of ref Lockfile;
	# XXX if O(n²) behaviour is a problem, use Readdir module
	for(;;){
		(n, e) := sys->dirread(fd);
		if(n <= 0)
			break;
		for (i := 0; i < n; i++) {
			for (l := lockl; l != nil; l = tl l)
				if ((hd l).d.name == e[i].name)
					break;
			if (l == nil) {
				e[i].qid = (maxqidpath++, 0, Sys->QTFILE);
				lockl = ref Lockfile(ref Lockqueue, nil, 0, 0, e[i]) :: lockl;
			}
		}
	}
	# remove all directories from list
	for (locks = nil; lockl != nil; lockl = tl lockl)
		if (((hd lockl).d.mode & Sys->DMDIR) == 0)
			locks = hd lockl :: locks;
}


fid2chan(srv: ref Styxserver, fid: int): ref Chan
{
	c := srv.fidtochan(fid);
	if (c == nil)
		raise "panic:bad fid";
	return c;
}

Lockqueue.put(q: self ref Lockqueue, s: ref Openreq)
{
        q.t = s :: q.t;
}

Lockqueue.get(q: self ref Lockqueue): ref Openreq
{
        s: ref Openreq;
        if(q.h == nil)
                (q.h, q.t) = (revrqlist(q.t), nil);

        if(q.h != nil)
                (s, q.h) = (hd q.h, tl q.h);

        return s;
}

Lockqueue.peek(q: self ref Lockqueue): ref Openreq
{
	s := q.get();
	if (s != nil)
		q.h = s :: q.h;
	return s;
}

doflush(l: list of ref Openreq, srv: ref Styxserver, tag: int): list of ref Openreq
{
	oldl := l;
	nl: list of ref Openreq;
	doneone := 0;
	while (l != nil) {
		oreq := hd l;
		if (oreq.srv != srv || (tag != -1 && oreq.tag != tag))
			nl = oreq :: nl;
		else
			doneone = 1;
		l = tl l;
	}
	if (doneone)
		return revrqlist(nl);
	else
		return oldl;
}

Lockqueue.flush(q: self ref Lockqueue, srv: ref Styxserver, tag: int)
{
	q.h = doflush(q.h, srv, tag);
	q.t = doflush(q.t, srv, tag);
}

# or inline
revrqlist(ls: list of ref Openreq) : list of ref Openreq
{
        rs: list of ref Openreq;
        while(ls != nil){
                rs = hd ls :: rs;
                ls = tl ls;
        }
        return rs;
}

# addr should be, e.g. tcp!*!2345
listener(addr: string, ch: chan of (ref Sys->FD, string, Uproc),
		sync: chan of (int, string), algs: list of string)
{
	addr = dial->netmkaddr(addr, "tcp", "33234");
	c := dial->announce(addr);
	if (c == nil) {
		sync <-= (-1, sys->sprint("cannot anounce on %s: %r", addr));
		return;
	}
	sync <-= (sys->pctl(0, nil), nil);
	for (;;) {
		nc := dial->listen(c);
		if (nc == nil) {
			ch <-= (nil, sys->sprint("listen failed: %r"), nil);
			return;
		}
		dfd := sys->open(nc.dir + "/data", Sys->ORDWR);
		if (dfd != nil) {
			if (algs == nil)
				ch <-= (dfd, nil, nil);
			else
				spawn authenticator(dfd, ch, algs);
		}
	}
}

# authenticate a connection, setting the user id appropriately,
# and then act as a server, performing file operations
# on behalf of the central process.
authenticator(dfd: ref Sys->FD, ch: chan of (ref Sys->FD, string, Uproc), algs: list of string)
{
	(fd, err) := auth->server(algs, authinfo, dfd, 1);
	if (fd == nil) {
		if (verbose)
			sys->fprint(stderr, "lockfs: authentication failed: %s\n", err);
		return;
	}
	uproc := chan of (ref Ureq, chan of (ref Sys->FD, string));
	ch <-= (fd, err, uproc);
	for (;;) {
		(req, reply) := <-uproc;
		if (req == nil)
			exit;
		reply <-= doreq(req);
	}
}

create(uproc: Uproc, file: string, omode: int, perm: int): (ref Sys->FD, string)
{
	return proxydoreq(uproc, ref Ureq.Create(file, omode, perm));
}

open(uproc: Uproc, file: string, omode: int): (ref Sys->FD, string)
{
	return proxydoreq(uproc, ref Ureq.Open(file, omode));
}

remove(uproc: Uproc, file: string): string
{
	return proxydoreq(uproc, ref Ureq.Remove(file)).t1;
}

wstat(uproc: Uproc, file: string, d: Sys->Dir): string
{
	return proxydoreq(uproc, ref Ureq.Wstat(file, d)).t1;
}

proxydoreq(uproc: Uproc, req: ref Ureq): (ref Sys->FD, string)
{
	if (uproc == nil)
		return doreq(req);
	reply := chan of (ref Sys->FD, string);
	uproc <-= (req, reply);
	return <-reply;
}

doreq(greq: ref Ureq): (ref Sys->FD, string)
{
	fd: ref Sys->FD;
	err: string;
	pick req := greq {
	Open =>
		if ((fd = sys->open(req.fname, req.omode)) == nil)
			err = sys->sprint("%r");
	Create =>
		if ((fd = sys->create(req.fname, req.omode, req.perm)) == nil)
			err = sys->sprint("%r");
	Remove =>
		if (sys->remove(req.fname) == -1)
			err = sys->sprint("%r");
	Wstat =>
		if (sys->wstat(req.fname, req.dir) == -1)
			err = sys->sprint("%r");
	}
	return (fd, err);
}

user(): string
{
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil){
		sys->fprint(stderr, "lockfs: can't open /dev/user: %r\n");
		raise "fail:no user";
	}

	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0) {
		sys->fprint(stderr, "lockfs: failed to read /dev/user: %r\n");
		raise "fail:no user";
	}

	return string buf[0:n];	
}

now(): int
{
	buf := array[128] of byte;
	sys->seek(timefd, big 0, 0);
	if ((n := sys->read(timefd, buf, len buf)) < 0)
		return 0;
	return int (big string buf[0:n] / big 1000000);
}
