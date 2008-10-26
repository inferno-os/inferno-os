implement Cs;

#
# Connection server translates net!machine!service into
# /net/tcp/clone 135.104.9.53!564
#

include "sys.m";
	sys:	Sys;

include "draw.m";

include "srv.m";
	srv: Srv;

include "bufio.m";
include "attrdb.m";
	attrdb: Attrdb;
	Attr, Db, Dbentry, Tuples: import attrdb;

include "ip.m";
	ip: IP;
include "ipattr.m";
	ipattr: IPattr;

include "arg.m";

Cs: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

# signature of dial-on-demand module
CSdial: module
{
	init:	fn(nil: ref Draw->Context): string;
	connect:	fn(): string;
};

Reply: adt
{
	fid:	int;
	pid:	int;
	addrs:	list of string;
	err:	string;
};

Cached: adt
{
	expire:	int;
	query:	string;
	addrs:	list of string;
};

Ncache: con 16;
cache:= array[Ncache] of ref Cached;
nextcache := 0;

rlist: list of ref Reply;

ndbfile := "/lib/ndb/local";
ndb: ref Db;
mntpt := "/net";
myname: string;

stderr: ref Sys->FD;

verbose := 0;
dialmod: CSdial;

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	attrdb = load Attrdb Attrdb->PATH;
	if(attrdb == nil)
		cantload(Attrdb->PATH);
	attrdb->init();
	ip = load IP IP->PATH;
	if(ip == nil)
		cantload(IP->PATH);
	ip->init();
	ipattr = load IPattr IPattr->PATH;
	if(ipattr == nil)
		cantload(IPattr->PATH);
	ipattr->init(attrdb, ip);

	svcname := "#scs";
	arg := load Arg Arg->PATH;
	if (arg == nil)
		cantload(Arg->PATH);
	arg->init(args);
	arg->setusage("cs [-v] [-x mntpt] [-f database] [-d dialmod]");
	while((c := arg->opt()) != 0)
		case c {
		'v' or 'D' =>
			verbose++;
		'd' =>	# undocumented hack to replace svc/cs/cs
			f := arg->arg();
			if(f != nil){
				dialmod = load CSdial f;
				if(dialmod == nil)
					cantload(f);
			}
		'f' =>
			ndbfile = arg->earg();
		'x' =>
			mntpt = arg->earg();
			svcname = "#scs"+svcpt(mntpt);
		* =>
			arg->usage();
		}

	if(arg->argv() != nil)
		arg->usage();
	arg = nil;

	srv = load Srv Srv->PATH;	# hosted Inferno only
	if(srv != nil)
		srv->init();

	sys->remove(svcname+"/cs");
	sys->unmount(svcname, mntpt);
	publish(svcname);
	if(sys->bind(svcname, mntpt, Sys->MBEFORE) < 0)
		error(sys->sprint("can't bind #s on %s: %r", mntpt));
	file := sys->file2chan(mntpt, "cs");
	if(file == nil)
		error(sys->sprint("can't make %s/cs: %r", mntpt));
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	refresh();
	if(dialmod != nil){
		e := dialmod->init(ctxt);
		if(e != nil)
			error(sys->sprint("can't initialise dial-on-demand: %s", e));
	}
	spawn cs(file);
}

svcpt(s: string): string
{
	for(i:=0; i<len s; i++)
		if(s[i] == '/')
			s[i] = '_';
	return s;
}

publish(dir: string)
{
	d := Sys->nulldir;
	d.mode = 8r777;
	if(sys->wstat(dir, d) < 0)
		sys->fprint(sys->fildes(2), "cs: can't publish %s: %r\n", dir);
}

cantload(m: string)
{
	error(sys->sprint("cannot load %s: %r", m));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "cs: %s\n", s);
	raise "fail:error";
}

refresh()
{
	myname = sysname();
	if(ndb == nil){
		ndb2 := Db.open(ndbfile);
		if(ndb2 == nil){
			err := sys->sprint("%r");
			ndb2 = Db.open("/lib/ndb/inferno");	# try to get service map at least
			if(ndb2 == nil)
				sys->fprint(sys->fildes(2), "cs: warning: can't open %s: %s\n", ndbfile, err);	# continue without it
		}
		ndb = Db.open(mntpt+"/ndb");
		if(ndb != nil)
			ndb = ndb.append(ndb2);
		else
			ndb = ndb2;
	}else
		ndb.reopen();
}

sysname(): string
{
	t := rf("/dev/sysname");
	if(t != nil)
		return t;
	t = rf("#e/sysname");
	if(t == nil){
		s := rf(mntpt+"/ndb");
		if(s != nil){
			db := Db.sopen(s);
			if(db != nil){
				(e, nil) := db.find(nil, "sys");
				if(e != nil)
					t = e.findfirst("sys");
			}
		}
	}
	if(t != nil){
		fd := sys->open("/dev/sysname", Sys->OWRITE);
		if(fd != nil)
			sys->fprint(fd, "%s", t);
	}
	return t;
}

rf(name: string): string
{
	fd := sys->open(name, Sys->OREAD);
	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

cs(file: ref Sys->FileIO)
{
	pidc := chan of int;
	donec := chan of ref Reply;
	for (;;) {
		alt {
		(nil, buf, fid, wc) := <-file.write =>
			cleanfid(fid);	# each write cancels previous requests
			if(dialmod != nil){
				e := dialmod->connect();
				if(e != nil){
					if(len e > 5 && e[0:5]=="fail:")
						e = e[5:];
					if(e == "")
						e = "unknown error";
					wc <-= (0, "cs: dial on demand: "+e);
					break;
				}
			}
			if(wc != nil){
				nbytes := len buf;
				query := string buf;
				if(query == "refresh"){
					refresh();
					wc <-= (nbytes, nil);
					break;
				}
				now := time();
				r := ref Reply;
				r.fid = fid;
				spawn request(r, query, nbytes, now, wc, pidc, donec);
				r.pid = <-pidc;
				rlist = r :: rlist;
			}

		(off, nbytes, fid, rc) := <-file.read =>
			if(rc != nil){
				r := findfid(fid);
				if(r != nil)
					reply(r, off, nbytes, rc);
				else
					rc <-= (nil, "unknown request");
			} else
				;	# cleanfid(fid);		# compensate for csendq in file2chan

		r := <-donec =>
			r.pid = 0;
		}
	}
}

findfid(fid: int): ref Reply
{
	for(rl := rlist; rl != nil; rl = tl rl){
		r := hd rl;
		if(r.fid == fid)
			return r;
	}
	return nil;
}

cleanfid(fid: int)
{
	rl := rlist;
	rlist = nil;
	for(; rl != nil; rl = tl rl){
		r := hd rl;
		if(r.fid != fid)
			rlist = r :: rlist;
		else
			killgrp(r.pid);
	}
}

killgrp(pid: int)
{
	if(pid != 0){
		fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
		if(fd == nil || sys->fprint(fd, "killgrp") < 0)
			sys->fprint(stderr, "cs: can't killgrp %d: %r\n", pid);
	}
}

request(r: ref Reply, query: string, nbytes: int, now: int, wc: chan of (int, string), pidc: chan of int, donec: chan of ref Reply)
{
	pidc <-= sys->pctl(Sys->NEWPGRP, nil);
	if(query != nil && query[0] == '!'){
		# general query
		(r.addrs, r.err) = genquery(query[1:]);
	}else{
		(r.addrs, r.err) = xlate(query, now);
		if(r.addrs == nil && r.err == nil)
			r.err = "cs: can't translate address";
	}
	if(r.err != nil){
		if(verbose)
			sys->fprint(stderr, "cs: %s: %s\n", query, r.err);
		wc <-= (0, r.err);
	} else
		wc <-= (nbytes, nil);
	donec <-= r;
}

reply(r: ref Reply, off: int, nbytes: int, rc: chan of (array of byte, string))
{
	if(r.err != nil){
		rc <-= (nil, r.err);
		return;
	}
	addr: string = nil;
	if(r.addrs != nil){
		addr = hd r.addrs;
		r.addrs = tl r.addrs;
	}
	off = 0;	# this version ignores offset
	rc <-= reads(addr, off, nbytes);
}

#
# return the file2chan reply for a read of the given string
#
reads(str: string, off, nbytes: int): (array of byte, string)
{
	bstr := array of byte str;
	slen := len bstr;
	if(off < 0 || off >= slen)
		return (nil, nil);
	if(off + nbytes > slen)
		nbytes = slen - off;
	if(nbytes <= 0)
		return (nil, nil);
	return (bstr[off:off+nbytes], nil);
}

lookcache(query: string, now: int): ref Cached
{
	for(i:=0; i<len cache; i++){
		c := cache[i];
		if(c != nil && c.query == query && now < c.expire){
			if(verbose)
				sys->print("cache: %s -> %s\n", query, hd c.addrs);
			return c;
		}
	}
	return nil;
}

putcache(query: string, addrs: list of string, now: int)
{
	ce := ref Cached;
	ce.expire = now+120;
	ce.query = query;
	ce.addrs = addrs;
	cache[nextcache] = ce;
	nextcache = (nextcache+1)%Ncache;
}

xlate(address: string, now: int): (list of string, string)
{
	n: int;
	l, rl, results: list of string;
	repl, netw, mach, service: string;

	ce := lookcache(address, now);
	if(ce != nil && ce.addrs != nil)
		return (ce.addrs, nil);

	(n, l) = sys->tokenize(address, "!\n");
	if(n < 2)
		return (nil, "bad format request");

	netw = hd l;
	if(netw == "net")
		netw = "tcp";	# TO DO: better (needs lib/ndb)
	if(!isnetwork(netw))
		return (nil, "network unavailable "+netw);
	l = tl l;

	if(!isipnet(netw)) {
		repl = mntpt + "/" + netw + "/clone ";
		for(;;){
			repl += hd l;
			if((l = tl l) == nil)
				break;
			repl += "!";
		}
		return (repl :: nil, nil);	# no need to cache
	}

	if(n != 3)
		return (nil, "bad format request");
	mach = hd l;
	service = hd tl l;

	if(!isnumeric(service)) {
		s := xlatesvc(netw, service);
		if(s == nil){
			if(srv != nil)
				s = srv->ipn2p(netw, service);
			if(s == nil)
				return (nil, "cs: can't translate service");
		}
		service = s;
	}

	attr := ipattr->dbattr(mach);
	if(mach == "*")
		l = "" :: nil;
	else if(attr != "ip") {
		# Symbolic server == "$SVC"
		if(mach[0] == '$' && len mach > 1 && ndb != nil){
			(s, nil) := ipattr->findnetattr(ndb, "sys", myname, mach[1:]);
			if(s == nil){
				names := dblook("infernosite", "", mach[1:]);
				if(names == nil)
					return (nil, "cs: can't translate "+mach);
				s = hd names;
			}
			mach = s;
			attr = ipattr->dbattr(mach);
		}
		if(attr == "sys"){
			results = dblook("sys", mach, "ip");
			if(results != nil)
				attr = "ip";
		}
		if(attr != "ip"){
			err: string;
			(results, err) = querydns(mach, "ip");
			if(err != nil)
				return (nil, err);
		}else if(results == nil)
			results = mach :: nil;
		l = results;
		if(l == nil){
			if(srv != nil)
				l = srv->iph2a(mach);
			if(l == nil)
				return (nil, "cs: unknown host");
		}
	} else
		l = mach :: nil;

	while(l != nil) {
		s := hd l;
		l = tl l;
		dnetw := netw;
		if(s != nil){
			(divert, err) := ipattr->findnetattr(ndb, "ip", s, "divert-"+netw);
			if(err == nil && divert != nil){
				dnetw = divert;
				if(!isnetwork(dnetw))
					return (nil, "network unavailable "+dnetw);	# XXX should only give up if all addresses fail?
			}
		}

		if(s != "")
			s[len s] = '!';
		s += service;

		repl = mntpt+"/"+dnetw+"/clone "+s;
		if(verbose)
			sys->fprint(stderr, "cs: %s!%s!%s -> %s\n", netw, mach, service, repl);

		rl = repl :: rl;
	}
	rl = reverse(rl);
	putcache(address, rl, now);
	return (rl, nil);
}

querydns(name: string, rtype: string): (list of string, string)
{
	fd := sys->open(mntpt+"/dns", Sys->ORDWR);
	if(fd == nil)
		return (nil, nil);
	if(sys->fprint(fd, "%s %s", name, rtype) < 0)
		return (nil, sys->sprint("%r"));
	rl: list of string;
	buf := array[256] of byte;
	sys->seek(fd, big 0, 0);
	while((n := sys->read(fd, buf, len buf)) > 0){
		# name rtype value
		(nf, fld) := sys->tokenize(string buf[0:n], " \t");
		if(nf != 3){
			sys->fprint(stderr, "cs: odd result from dns: %s\n", string buf[0:n]);
			continue;
		}
		rl = hd tl tl fld :: rl;
	}
	return (reverse(rl), nil);
}

dblook(attr: string, val: string, rattr: string): list of string
{
	rl: list of string;
	ptr: ref Attrdb->Dbptr;
	for(;;){
		e: ref Dbentry;
		(e, ptr) = ndb.findbyattr(ptr, attr, val, rattr);
		if(e == nil)
			break;
		for(l := e.findbyattr(attr, val, rattr); l != nil; l = tl l){
			(nil, al) := hd l;
			for(; al != nil; al = tl al)
				if(!inlist((hd al).val, rl))
					rl = (hd al).val :: rl;
		}
	}
	return reverse(rl);
}

inlist(s: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

reverse(l: list of string): list of string
{
	t: list of string;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}

isnumeric(a: string): int
{
	i, c: int;

	for(i = 0; i < len a; i++) {
		c = a[i];
		if(c < '0' || c > '9')
			return 0;
	}
	return 1;
}

nets: list of string;

isnetwork(s: string) : int
{
	if(find(s, nets))
		return 1;
	(ok, nil) := sys->stat(mntpt+"/"+s+"/clone");
	if(ok >= 0) {
		nets = s :: nets;
		return 1;
	}
	return 0;
}

find(e: string, l: list of string) : int
{
	for(; l != nil; l = tl l)
		if (e == hd l)
			return 1;
	return 0;
}

isipnet(s: string) : int
{
	return s == "net" || s == "tcp" || s == "udp" || s == "il";
}

xlatesvc(proto: string, s: string): string
{
	if(ndb == nil || s == nil || isnumeric(s))
		return s;
	(e, nil) := ndb.findbyattr(nil, proto, s, "port");
	if(e == nil)
		return nil;
	matches := e.findbyattr(proto, s, "port");
	if(matches == nil)
		return nil;
	(ts, al) := hd matches;
	restricted := "";
	if(ts.hasattr("restricted"))
		restricted = "!r";
	if(verbose > 1)
		sys->print("%s=%q port=%s%s\n", proto, s, (hd al).val, restricted);
	return (hd al).val+restricted;
}

time(): int
{
	timefd := sys->open("/dev/time", Sys->OREAD);
	if(timefd == nil)
		return 0;
	buf := array[128] of byte;
	sys->seek(timefd, big 0, 0);
	n := sys->read(timefd, buf, len buf);
	if(n < 0)
		return 0;
	return int ((big string buf[0:n]) / big 1000000);
}

#
# general query: attr1=val1 attr2=val2 ... finds matching tuple(s)
#	where attr1 is the key and val1 can't be *
#
genquery(query: string): (list of string, string)
{
	(tups, err) := attrdb->parseline(query, 0);
	if(err != nil)
		return (nil, "bad query: "+err);
	if(tups == nil)
		return (nil, "bad query");
	pairs := tups.pairs;
	a0 := (hd pairs).attr;
	if(a0 == "ipinfo")
		return (nil, "ipinfo not yet supported");
	v0 := (hd pairs).val;

	# if((a0 == "dom" || a0 == "ip") && v0 != nil){
	# 	query dns ...
	# }

	ptr: ref Attrdb->Dbptr;
	e: ref Dbentry;
	for(;;){
		(e, ptr) = ndb.findpair(ptr, a0, v0);
		if(e == nil)
			break;
		for(l := e.lines; l != nil; l = tl l)
			if(qmatch(hd l, tl pairs)){
				ls: list of string;
				for(l = e.lines; l != nil; l = tl l)
					ls = tuptext(hd l) :: ls;
				return (reverse(ls), nil);
			}
	}
	return  (nil, "no match");
}

#
# see if set of tuples t contains every non-* attr/val pair
#
qmatch(t: ref Tuples, av: list of ref Attr): int
{
Match:
	for(; av != nil; av = tl av){
		a := hd av;
		for(pl := t.pairs; pl != nil; pl = tl pl)
			if((hd pl).attr == a.attr &&
			    (a.val == "*" || a.val == (hd pl).val))
				continue Match;
		return 0;
	}
	return 1;
}

tuptext(t: ref Tuples): string
{
	s: string;
	for(pl := t.pairs; pl != nil; pl = tl pl){
		p := hd pl;
		if(s != nil)
			s[len s] = ' ';
		s += sys->sprint("%s=%q", p.attr, p.val);
	}
	return s;
}
