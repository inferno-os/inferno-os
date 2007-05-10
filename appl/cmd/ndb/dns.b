implement DNS;

#
# domain name service
#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#
# RFCs: 1034, 1035, 2181, 2308
#
# TO DO:
#	server side:
#		database; inmyzone; ptr generation; separate zone transfer
#	currently doesn't implement loony rules on case
#	limit work
#	check data
#	Call
#	ipv6
#

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;

include "draw.m";

include "bufio.m";

include "srv.m";
	srv: Srv;

include "ip.m";
	ip: IP;
	IPaddrlen, IPaddr, IPv4off, Udphdrlen, Udpraddr, Udpladdr, Udprport, Udplport: import ip;

include "arg.m";

include "attrdb.m";
	attrdb: Attrdb;
	Db, Dbentry, Tuples: import attrdb;

include "ipattr.m";
	ipattr: IPattr;
	dbattr: import ipattr;

DNS: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Reply: adt
{
	fid:	int;
	pid:	int;
	query:	string;
	attr:	string;
	addrs:	list of string;
	err:	string;
};

rlist: list of ref Reply;

dnsfile := "/lib/ndb/local";
myname: string;
mntpt := "/net";
DNSport: con 53;
debug := 0;
referdns := 0;
usehost := 1;
now: int;

servers: list of string;

# domain name from dns/db
domain: string;
dnsdomains: list of string;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	arg := load Arg Arg->PATH;
	if(arg == nil)
		cantload(Arg->PATH);
	arg->init(args);
	arg->setusage("dns [-Drh] [-f dnsfile] [-x mntpt]");
	svcname := "#sdns";
	while((c := arg->opt()) != 0)
		case c {
		'D' =>
			debug = 1;
		'f' =>	
			dnsfile = arg->earg();
		'h' =>
			usehost = 0;
		'r' =>
			referdns = 1;
		'x' =>
			mntpt = arg->earg();
			svcname = "#sdns"+svcpt(mntpt);
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args != nil)
		arg->usage();
	arg = nil;

	if(usehost){
		srv = load Srv Srv->PATH;	# hosted Inferno only
		if(srv != nil)
			srv->init();
	}
	ip = load IP IP->PATH;
	if(ip == nil)
		cantload(IP->PATH);
	ip->init();
	attrdb = load Attrdb Attrdb->PATH;
	if(attrdb == nil)
		cantload(Attrdb->PATH);
	attrdb->init();
	ipattr = load IPattr IPattr->PATH;
	if(ipattr == nil)
		cantload(IPattr->PATH);
	ipattr->init(attrdb, ip);

	sys->pctl(Sys->NEWPGRP | Sys->FORKFD, nil);
	myname = sysname();
	stderr = sys->fildes(2);
	readservers();
	now = time();
	sys->remove(svcname+"/dns");
	sys->unmount(svcname, mntpt);
	publish(svcname);
	if(sys->bind(svcname, mntpt, Sys->MBEFORE) < 0)
		error(sys->sprint("can't bind #s on %s: %r", mntpt));
	file := sys->file2chan(mntpt, "dns");
	if(file == nil)
		error(sys->sprint("can't make %s/dns: %r", mntpt));
	sync := chan of int;
	spawn dnscache(sync);
	<-sync;
	spawn dns(file);
}

publish(dir: string)
{
	d := Sys->nulldir;
	d.mode = 8r777;
	if(sys->wstat(dir, d) < 0)
		sys->fprint(sys->fildes(2), "cs: can't publish %s: %r\n", dir);
}

svcpt(s: string): string
{
	for(i:=0; i<len s; i++)
		if(s[i] == '/')
			s[i] = '_';
	return s;
}

cantload(s: string)
{
	error(sys->sprint("can't load %s: %r", s));
}

error(s: string)
{
	sys->fprint(stderr, "dns: %s\n", s);
	raise "fail:error";
}

dns(file: ref Sys->FileIO)
{
	pidc := chan of int;
	donec := chan of ref Reply;
	for(;;){
		alt {
		(nil, buf, fid, wc) := <-file.write =>
			now = time();
			cleanfid(fid);	# each write cancels previous requests
			if(wc != nil){
				r := ref Reply;
				r.fid = fid;
				spawn request(r, buf, wc, pidc, donec);
				r.pid = <-pidc;
				rlist = r :: rlist;
			}

		(off, nbytes, fid, rc) := <-file.read =>
			now = time();
			if(rc != nil){
				r := findfid(fid);
				if(r != nil)
					reply(r, off, nbytes, rc);
				else
					rc <-= (nil, "unknown request");
			}

		r := <-donec =>
			now = time();
			r.pid = 0;
			if(r.err != nil)
				cleanfid(r.fid);
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
			sys->fprint(stderr, "dns: can't killgrp %d: %r\n", pid);
	}
}

request(r: ref Reply, data: array of byte, wc: chan of (int, string), pidc: chan of int, donec: chan of ref Reply)
{
	pidc <-= sys->pctl(Sys->NEWPGRP, nil);
	query := string data;
	for(i := 0; i < len query; i++)
		if(query[i] == ' ')
			break;
	r.query = query[0:i];
	for(; i < len query && query[i] == ' '; i++)
		;
	r.attr = query[i:];
	attr := rrtype(r.attr);
	if(attr < 0)
		r.err = "unknown type";
	else
		(r.addrs, r.err) = dnslookup(r.query, attr);
	if(r.addrs == nil && r.err == nil)
		r.err = "not found";
	if(r.err != nil){
		if(debug)
			sys->fprint(stderr, "dns: %s: %s\n", query, r.err);
		wc <-= (0, "dns: "+r.err);
	} else
		wc <-= (len data, nil);
	donec <-= r;
}

reply(r: ref Reply, off: int, nbytes: int, rc: chan of (array of byte, string))
{
	if(r.err != nil || r.addrs == nil){
		rc <-= (nil, r.err);
		return;
	}
	addr: string;
	if(r.addrs != nil){
		addr = hd r.addrs;
		r.addrs = tl r.addrs;
	}
	off = 0;	# this version ignores offsets
#	rc <-= reads(r.query+" "+r.attr+" "+addr, off, nbytes);
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

sysname(): string
{
	t := rf("/dev/sysname");
	if(t != nil)
		return t;
	t = rf("#e/sysname");
	if(t == nil){
		s := rf(mntpt+"/ndb");
		if(s != nil){
			db := Db.sopen(t);
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
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

samefile(d1, d2: Sys->Dir): int
{
	# ``it was black ... it was white!  it was dark ...  it was light! ah yes, i remember it well...''
	return d1.dev==d2.dev && d1.dtype==d2.dtype &&
			d1.qid.path==d2.qid.path && d1.qid.vers==d2.qid.vers &&
			d1.mtime==d2.mtime;
}

#
# database
#	dnsdomain=	suffix to add to unqualified unrooted names
#	dns=			dns server to try
#	dom=		domain name
#	ip=			IP address
#	ns=			name server
#	soa=
#	soa=delegated
#	infernosite=	set of site-wide parameters
#

#
# basic Domain Name Service resolver
#

laststat := 0;	# time last stat'd (to reduce churn)
dnsdb: ref Db;

readservers(): list of string
{
	if(laststat != 0 && now < laststat+2*60)
		return servers;
	laststat = now;
	if(dnsdb == nil){
		db := Db.open(dnsfile);
		if(db == nil){
			sys->fprint(stderr, "dns: can't open %s: %r\n", dnsfile);
			return nil;
		}
		dyndb := Db.open(mntpt+"/ndb");
		if(dyndb != nil)
			dnsdb = dyndb.append(db);
		else
			dnsdb = db;
	}else{
		if(!dnsdb.changed())
			return servers;
		dnsdb.reopen();
	}
	if((l := dblooknet("sys", myname, "dnsdomain")) == nil)
		l = dblook("infernosite", "", "dnsdomain");
	dnsdomains = "" :: l;
	if((l = dblooknet("sys", myname, "dns")) == nil)
		l = dblook("infernosite", "", "dns");
	servers = l;
#	zones := dblook("soa", "", "dom");
#printlist("zones", zones);
	if(debug)
		printlist("dnsdomains", dnsdomains);
	if(debug)
		printlist("servers", servers);
	return servers;
}

printlist(w: string, l: list of string)
{
	sys->print("%s:", w);
	for(; l != nil; l = tl l)
		sys->print(" %q", hd l);
	sys->print("\n");
}

dblookns(dom: string): list of ref RR
{
	domns := dblook("dom", dom, "ns");
	hosts: list of ref RR;
	for(; domns != nil; domns = tl domns){
		s := hd domns;
		if(debug)
			sys->print("dns db: dom=%s ns=%s\n", dom, s);
		ipl: list of ref RR = nil;
		addrs := dblook("dom", s, "ip");
		for(; addrs != nil; addrs = tl addrs){
			a := parseip(hd addrs);
			if(a != nil){
				ipl = ref RR.A(s, Ta, Cin, now+60, 0, a) :: ipl;
				if(debug)
					sys->print("dom=%s ip=%s\n", s, hd addrs);
			}
		}
		if(ipl != nil){
			# only use ones for which we've got addresses
			cachec <-= (ipl, 0);
			hosts = ref RR.Host(dom, Tns, Cin, now+60, 0, s) :: hosts;
		}
	}
	if(hosts == nil){
		if(debug)
			sys->print("dns: no ns for dom=%s in db\n", dom);
		return nil;
	}
	cachec <-= (hosts, 0);
	cachec <-= Sync;
	return hosts;
}

defaultresolvers(): list of ref NS
{
	resolvers := readservers();
	al: list of ref RR;
	for(; resolvers != nil; resolvers = tl resolvers){
		nm := hd resolvers;
		a := parseip(nm);
		if(a == nil){
			# try looking it up as a domain name with an ip address
			for(addrs := dblook("dom", nm, "ip"); addrs != nil; addrs = tl addrs){
				a = parseip(hd addrs);
				if(a != nil)
					al = ref RR.A("defaultns", Ta, Cin, now+60, 0, a) :: al;
			}
		}else
			al = ref RR.A("defaultns", Ta, Cin, now+60, 0, a) :: al;
	}
	if(al == nil){
		if(debug)
			sys->print("dns: no default resolvers\n");
		return nil;
	}
	return ref NS("defaultns", al, 1, now+60) :: nil;
}

dblook(attr: string, val: string, rattr: string): list of string
{
	rl: list of string;
	ptr: ref Attrdb->Dbptr;
	for(;;){
		e: ref Dbentry;
		(e, ptr) = dnsdb.findbyattr(ptr, attr, val, rattr);
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

#
# starting from the ip= associated with attr=val, search over all
# containing networks for the nearest values of rattr
#
dblooknet(attr: string, val: string, rattr: string): list of string
{
#sys->print("dblooknet: %s=%s -> %s\n", attr, val, rattr);
	(results, nil) := ipattr->findnetattrs(dnsdb, attr, val, rattr::nil);
	rl: list of string;
	for(; results != nil; results = tl results){
		(nil, nattrs) := hd results;
		for(; nattrs != nil; nattrs = tl nattrs){
			na := hd nattrs;
			if(na.name == rattr){
				for(pairs := na.pairs; pairs != nil; pairs = tl pairs)
					if((s := (hd pairs).val) != nil && !inlist(s, rl))
						rl = s :: rl;
			}
		}
	}
	if(rl == nil)
		return dblook(attr, val, rattr);
	return reverse(rl);
}

inlist(s: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

reverse[T](l: list of T): list of T
{
	r: list of T;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

append(h: list of string, s: string): list of string
{
	if(h == nil)
		return s :: nil;
	return hd h :: append(tl h, s);
}

#
# subset of RR types
#
Ta: con 1;
Tns: con 2;
Tcname: con 5;
Tsoa: con 6;
Tmb: con 7;
Tptr: con 12;
Thinfo: con 13;
Tmx: con 15;
Tall: con 255;

#
# classes
#
Cin: con 1;
Call: con 255;

#
# opcodes
#
Oquery: con 0<<11;	# normal query
Oinverse: con 1<<11;	# inverse query
Ostatus:	con 2<<11;	# status request
Omask:	con 16rF<<11;	# mask for opcode

#
# response codes
#
Rok:	con 0;
Rformat:	con 1;	# format error
Rserver:	con 2;	# server failure
Rname:	con 3;	# bad name
Runimplemented: con 4;	# unimplemented operation
Rrefused:	con 5;	# permission denied, not supported
Rmask:	con 16rF;	# mask for response

#
# other flags in opcode
#
Fresp:	con 1<<15;	# message is a response
Fauth:	con 1<<10;	# true if an authoritative response
Ftrunc:	con 1<<9;		# truncated message
Frecurse:	con 1<<8;		# request recursion
Fcanrecurse:	con 1<<7;	# server can recurse

QR: adt {
	name: string;
	rtype: int;
	class: int;

	text:	fn(q: self ref QR): string;
};

RR: adt {
	name: string;
	rtype: int;
	class: int;
	ttl: int;
	flags:	int;
	pick {
	Error =>
		reason:	string;	# cached negative
	Host =>
		host:	string;
	Hinfo =>
		cpu:	string;
		os:	string;
	Mx =>
		pref:	int;
		host:	string;
	Soa =>
		soa:	ref SOA;
	A or
	Other =>
		rdata:	array of byte;
	}

	islive:	fn(r: self ref RR): int;
	outlives:	fn(a: self ref RR, b: ref RR): int;
	match:	fn(a: self ref RR, b: ref RR): int;
	text:	fn(a: self ref RR): string;
};

SOA: adt {
	mname:	string;
	rname:	string;
	serial:	int;
	refresh:	int;
	retry:	int;
	expire:	int;
	minttl:	int;

	text:	fn(nil: self ref SOA): string;
};

DNSmsg: adt {
	id: 	int;
	flags:	int;
	qd: list of ref QR;
	an: list of ref RR;
	ns: list of ref RR;
	ar: list of ref RR;
	err: string;

	pack:	fn(m: self ref DNSmsg, hdrlen: int): array of byte;
	unpack:	fn(a: array of byte): ref DNSmsg;
	text:	fn(m: self ref DNSmsg): string;
};

NM: adt {
	name:	string;
	rr:	list of ref RR;
	stats:	ref Stats;
};

Stats: adt {
	rtt:	int;
};

cachec: chan  of (list of ref RR, int);
cache: array of list of ref NM;
Sync: con (nil, 0);	# empty list sent to ensure that last cache update done

hash(s: string): array of list of ref NM
{
	h := 0;
	for(i:=0; i<len s; i++){	# hashpjw
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a'-'A';
		h = (h<<4) + c;
		if((g := h & int 16rF0000000) != 0)
			h ^= ((g>>24) & 16rFF) | g;
	}
	return cache[(h&~(1<<31))%len cache:];
}

lower(s: string): string
{
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c >= 'A' && c <= 'Z'){
			n := s;
			for(; i < len n; i++){
				c = n[i];
				if(c >= 'A' && c <= 'Z')
					n[i] = c+('a'-'A');
			}
			return n;
		}
	}
	return s;
}

#
# split rrl into a list of those RRs that match rr and a list of those that don't
#
partrrl(rr: ref RR, rrl: list of ref RR): (list of ref RR, list of ref RR)
{
	m: list of ref RR;
	nm: list of ref RR;
	name := lower(rr.name);
	for(; rrl != nil; rrl = tl rrl){
		t := hd rrl;
		if(t.rtype == rr.rtype && t.class == rr.class &&
		   (t.name == name || lower(t.name) == name))
			m = t :: m;
		else
			nm = t :: nm;
	}
	return (m, nm);
}

copyrrl(rrl: list of ref RR): list of ref RR
{
	nl: list of ref RR;
	for(; rrl != nil; rrl = tl rrl)
		nl = ref *hd rrl :: nl;
#	return revrrl(rrl);
	return rrl;	# probably don't care about order
}

dnscache(sync: chan of int)
{
	cache = array[32] of list of ref NM;
	cachec = chan of (list of ref RR, int);
	sync <-= sys->pctl(0, nil);
	for(;;){
		(rrl, flags) := <-cachec;
		#now = time();
	  List:
		while(rrl != nil){
			rrset: list of ref RR;
			(rrset, rrl) = partrrl(hd rrl, rrl);
			rr := hd rrset;
			rr.flags = flags;
			name := lower(rr.name);
			hb := hash(name);
			for(ces := hb[0]; ces != nil; ces = tl ces){
				ce := hd ces;
				if(ce.name == name){
					rr.name = ce.name;	# share string
					x := ce.rr;
					ce.rr = insertrrset(ce.rr, rr, rrset);
					if(x != ce.rr && debug)
						sys->print("insertrr %s:%s\n", name, rrsettext(rrset));
					continue List;
				}
			}
			if(debug)
				sys->print("newrr %s:%s\n", name, rrsettext(rrset));
			hb[0] = ref NM(name, rrset, nil) :: hb[0];
		}
	}
}

lookcache(name: string, rtype: int, rclass: int): (list of ref RR, string)
{
	results: list of ref RR;
	name = lower(name);
	for(ces := hash(name)[0]; ces != nil; ces = tl ces){
		ce := hd ces;
		if(ce.name == name){
			for(zl := ce.rr; zl != nil; zl = tl zl){
				r := hd zl;
				if((r.rtype == rtype || r.rtype == Tall || rtype == Tall) && r.class == rclass && r.name == name && r.islive()){
					pick ar := r {
					Error =>
						if(rtype != Tall || ar.reason != "resource does not exist"){
							if(debug)
								sys->print("lookcache: %s[%s]: !%s\n", name, rrtypename(rtype), ar.reason);
							return (nil, ar.reason);
						}
					* =>
						results = ref *r :: results;
					}
				}
			}
		}
	}
	if(debug)
		sys->print("lookcache: %s[%s]: %s\n", name, rrtypename(rtype), rrsettext(results));
	return (results, nil);
}

#
# insert RRset new in existing list of RRsets rrl
# if that's desirable (it's the whole RRset or nothing, see rfc2181)
#
insertrrset(rrl: list of ref RR, rr: ref RR, new: list of ref RR): list of ref RR
{
	# TO DO: expire entries
	match := 0;
	for(l := rrl; l != nil; l = tl l){
		orr := hd l;
		if(orr.rtype == rr.rtype && orr.class == rr.class){	# name already known to match
			match = 1;
			if(!orr.islive())
				break;	# prefer new, unexpired data
			if(tagof rr == tagof RR.Error && tagof orr != tagof RR.Error)
				return rrl;	# prefer unexpired positive
			if(rr.flags & Fauth)
				break;	# prefer newly-arrived authoritative data
			if(orr.flags & Fauth)
				return rrl;		# prefer authoritative data
			if(orr.outlives(rr))
				return rrl;		# prefer longer-lived data
		}
	}
	if(match){
		# strip out existing RR set
		l = rrl;
		rrl = nil;
		for(; l != nil; l = tl l){
			orr := hd l;
			if((orr.rtype != rr.rtype || orr.class != rr.class) && orr.islive()){
				rrl = orr :: rrl;}
		}
	}
	# add new RR set
	for(; new != nil; new = tl new){
		nrr := hd new;
		nrr.name = rr.name;
		rrl = nrr :: rrl;
	}
	return rrl;
}

rrsettext(rrl: list of ref RR): string
{
	s := "";
	for(; rrl != nil; rrl = tl rrl)
		s += " ["+(hd rrl).text()+"]";
	return s;
}

QR.text(qr: self ref QR): string
{
	s := sys->sprint("%s %s", qr.name, rrtypename(qr.rtype));
	if(qr.class != Cin)
		s += sys->sprint(" [c=%d]", qr.class);
	return s;
}

RR.islive(rr: self ref RR): int
{
	return rr.ttl >= now;
}

RR.outlives(a: self ref RR, b: ref RR): int
{
	return a.ttl > b.ttl;
}

RR.match(a: self ref RR, b: ref RR): int
{
	# compare content, not ttl
	return a.rtype == b.rtype && a.class == b.class && a.name == b.name;
}

RR.text(rr: self ref RR): string
{
	s := sys->sprint("%s %s", rr.name, rrtypename(rr.rtype));
	pick ar := rr {
	Host =>
		s += sys->sprint("\t%s", ar.host);
	Hinfo =>
		s += sys->sprint("\t%s %s", ar.cpu, ar.os);
	Mx =>
		s += sys->sprint("\t%ud %s", ar.pref, ar.host);
	Soa =>
		s += sys->sprint("\t%s", ar.soa.text());
	A =>
		if(len ar.rdata == 4){
			a := ar.rdata;
			s += sys->sprint("\t%d.%d.%d.%d", int a[0], int a[1], int a[2], int a[3]);
		}
	Error =>
		s += sys->sprint("\t!%s", ar.reason);
	}
	return s;
}

SOA.text(soa: self ref SOA): string
{
	return sys->sprint("%s %s %ud %ud %ud %ud %ud", soa.mname, soa.rname,
			soa.serial, soa.refresh, soa.retry, soa.expire, soa.minttl);
}

NS: adt {
	name:	string;
	addr:	list of ref RR;
	canrecur:	int;
	ttl:	int;
};

dnslookup(name: string, attr: int): (list of string, string)
{
	case attr {
	Ta =>
		case dbattr(name) {
		"sys" =>
			# could apply domains
			;
		"dom" =>
			;
		* =>
			return (nil, "invalid host name");
		}
		if(srv != nil){	# try the host's map first
			l := srv->iph2a(name);
			if(l != nil)
				return (fullresult(name, "ip", l), nil);
		}
	Tptr =>
		if(srv != nil){	# try host's map first
			l := srv->ipa2h(arpa2addr(name));
			if(l != nil)
				return (fullresult(name, "ptr", l), nil);
		}
	}
	return dnslookup1(name, attr);
}

fullresult(name: string, attr: string, l: list of string): list of string
{
	rl: list of string;
	for(; l != nil; l = tl l)
		rl = sys->sprint("%s %s\t%s", name, attr, hd l) :: rl;
	return reverse(rl);
}

arpa2addr(a: string): string
{
	(nil, flds) := sys->tokenize(a, ".");
	rl: list of string;
	for(; flds != nil && lower(s := hd flds) != "in-addr"; flds = tl flds)
		rl = s :: rl;
	dom: string;
	for(; rl != nil; rl = tl rl){
		if(dom != nil)
			dom[len dom] = '.';
		dom += hd rl;
	}
	return dom;
}

dnslookup1(label: string, attr: int): (list of string, string)
{
	(rrl, err) := fulldnsquery(label, attr, 0);
	if(err != nil || rrl == nil)
		return (nil, err);
	r: list of string;
	for(; rrl != nil; rrl = tl rrl)
		r = (hd rrl).text() :: r;
	return (reverse(r), nil);
}

trimdot(s: string): string
{
	while(s != nil && s[len s - 1] == '.')
		s = s[0:len s -1];
	return s;
}

parent(s: string): string
{
	if(s == "")
		return ".";
	for(i := 0; i < len s; i++)
		if(s[i] == '.')
			return s[i+1:];
	return "";
}

rootservers(): list of ref NS
{
	slist := ref NS("a.root-servers.net",
		ref RR.A("a.root-servers.net", Ta, Cin, 1<<31, 0,
			array[] of {byte 198, byte 41, byte 0, byte 4})::nil, 0, 1<<31) :: nil;
	return slist;
}

#
# this broadly follows the algorithm given in RFC 1034
# as adjusted and qualified by several other RFCs.
# `label' is 1034's SNAME, `attr' is `STYPE'
#
# TO DO:
#	keep statistics for name servers

fulldnsquery(label: string, attr: int, depth: int): (list of ref RR, string)
{
	slist: list of ref NS;
	fd: ref Sys->FD;
	if(depth > 10)
		return (nil, "dns loop");
	ncname := 0;
Step1:
	for(tries:=0; tries<10; tries++){

		# 1. see if in local information, and if so, return it
		(x, err) := lookcache(label, attr, Cin);
		if(x != nil)
			return (x, nil);
		if(err != nil)
			return (nil, err);
		if(attr != Tcname){
			if(++ncname > 10)
				return (nil, "cname alias loop");
			(x, err) = lookcache(label, Tcname, Cin);
			if(x != nil){
				pick rx := hd x {
				Host =>
					label  = rx.host;
					continue;
				}
			}
		}

		# 2. find the best servers to ask
		slist = nil;
		for(d := trimdot(label); d != "."; d = parent(d)){
			nsl: list of ref RR;
			(nsl, err) = lookcache(d, Tns, Cin);
			if(nsl == nil)
				nsl = dblookns(d);
			# add each to slist; put ones with known addresses first
			known: list of ref NS = nil;
			for(; nsl != nil; nsl = tl nsl){
				pick ns := hd nsl {
				Host =>
					(addrs, err2) := lookcache(ns.host, Ta, Cin);
					if(addrs != nil)
						known = ref NS(ns.host, addrs, 0, 1<<31) :: known;
					else if(err2 == nil)
						slist = ref NS(ns.host, nil, 0, 1<<31) :: slist;
				}
					
			}
			for(; known != nil; known = tl known)
				slist = hd known :: slist;
			if(slist != nil)
				break;
		}
		# if no servers, resort to safety belt
		if(slist == nil){
			slist = defaultresolvers();
			if(slist == nil){
				slist = rootservers();
				if(slist == nil)
					return (nil, "no dns servers configured");
			}
		}
		(id, query, err1) := mkquery(attr, Cin, label);
		if(err1 != nil){
			sys->fprint(stderr, "dns: %s\n", err1);
			return (nil, err1);
		}

		if(debug)
			printnslist(sys->sprint("ns for %s: ", d), slist);

		# 3. send them queries until one returns a response
		for(qset := slist; qset != nil; qset = tl qset){
			ns := hd qset;
			if(ns.addr == nil){
				if(debug)
					sys->print("recursive[%d] query for %s address\n", depth+1, ns.name);
				(ns.addr, nil) = fulldnsquery(ns.name, Ta, depth+1);
				if(ns.addr == nil)
					continue;
			}
			if(fd == nil){
				fd = udpport();
				if(fd == nil)
					return (nil, sys->sprint("%r"));
			}
			(dm, err2) := udpquery(fd, id, query, ns.name, hd ns.addr);
			if(dm == nil){
				sys->fprint(stderr, "dns: %s: %s\n", ns.name, err2);
				# TO DO: remove from slist
				continue;
			}
			# 4. analyse the response
			#	a. answers the question or has Rname, cache it and return to client
			#	b. delegation to other NS? cache and goto step 2.
			#	c. if response is CNAME and QTYPE!=CNAME change SNAME to the
			#		canonical name (data) of the CNAME RR and goto step 1.
			#	d. if response is server failure or otherwise odd, delete server from SLIST
			#		and goto step 3.
			auth := (dm.flags & Fauth) != 0;
			soa: ref RR.Soa;
			(soa, dm.ns) = soaof(dm.ns);
			if((dm.flags & Rmask) != Rok){
				# don't repeat the request on an error
				#  TO DO: should return `best error'
				if(tl qset != nil && ((dm.flags & Rmask) != Rname || !auth))
					continue;
				cause := reason(dm.flags & Rmask);
				if(auth && soa != nil){
					# rfc2038 says to cache soa with cached negatives, and the
					# negative to be retrieved for all attributes if name does not exist
					if((ttl := soa.soa.minttl) > 0)
						ttl += now;
					else
						ttl = now+10*60;
					a := attr;
					if((dm.flags & Rmask) == Rname)
						a = Tall;
					cachec <-= (ref RR.Error(label, a, Cin, ttl, auth, cause)::soa::nil, auth);
				}
				return (nil, cause);
			}
			if(dm.an != nil){
				if(1 && dm.ns != nil)
					cachec <-= (dm.ns, 0);
				if(1 && dm.ar != nil)
					cachec <-= (dm.ar, 0);
				cachec <-= (dm.an, auth);
				cachec <-= Sync;
				if(isresponse(dm, attr))
					return (dm.an, nil);
				if(attr != Tcname && (cn := cnameof(dm)) != nil){
					if(++ncname > 10)
						return (nil, "cname alias loop");
					label = cn;
					continue Step1;
				}
			}
			if(auth){
				if(soa != nil && (ttl := soa.soa.minttl) > 0)
					ttl += now;
				else
					ttl = now+10*60;
				cachec <-= (ref RR.Error(label, attr, Cin, ttl, auth, "resource does not exist")::soa::nil, auth);
				return (nil, "resource does not exist");
			}
			if(isdelegation(dm)){
				# cache valid name servers and hints
				cachec <-= (dm.ns, 0);
				if(dm.ar != nil)
					cachec <-= (dm.ar, 0);
				cachec <-= Sync;
				continue Step1;
			}
		}
	}
	return (nil, "server failed");
}

isresponse(dn: ref DNSmsg, attr: int): int
{
	if(dn == nil || dn.an == nil)
		return 0;
	return (hd dn.an).rtype == attr;
}

cnameof(dn: ref DNSmsg): string
{
	if(dn != nil && dn.an != nil && (rr := hd dn.an).rtype == Tcname)
		pick ar := rr {
		Host =>
			return ar.host;
		}
	return nil;
}

soaof(rrl: list of ref RR): (ref RR.Soa, list of ref RR)
{
	for(l := rrl; l != nil; l = tl l)
		pick rr := hd l {
		Soa =>
			rest := tl l;
			for(; rrl != l; rrl = tl rrl)
				if(tagof hd rrl != tagof RR.Soa)	# (just in case)
					rest = hd rrl :: rest;
			return (rr, rest);
		}
	return (nil, rrl);
}

isdelegation(dn: ref DNSmsg): int
{
	if(dn.an != nil)
		return 0;
	for(al := dn.ns; al != nil; al = tl al)
		if((hd al).rtype == Tns)
			return 1;
	return 0;
}

printnslist(prefix: string, nsl: list of ref NS)
{
	s := prefix;
	for(; nsl != nil; nsl = tl nsl){
		ns := hd nsl;
		s += sys->sprint(" [%s %s]", ns.name, rrsettext(ns.addr));
	}
	sys->print("%s\n", s);
}

#
# DNS message format
#

Udpdnslim: con 512;

Labels: adt {
	names:	list of (string, int);

	new:	fn(): ref Labels;
	look:	fn(labs: self ref Labels, s: string): int;
	install:	fn(labs: self ref Labels, s: string, o: int);
};

Labels.new(): ref Labels
{
	return ref Labels;
}

Labels.look(labs: self ref Labels, s: string): int
{
	for(nl := labs.names; nl != nil; nl = tl nl){
		(t, o) := hd nl;
		if(s == t)
			return 16rC000 | o;
	}
	return 0;
}

Labels.install(labs: self ref Labels, s: string, off: int)
{
	labs.names = (s, off) :: labs.names;
}

put2(a: array of byte, o: int, val: int): int
{
	if(o < 0)
		return o;
	if(o + 2 > len a)
		return -o;
	a[o] = byte (val>>8);
	a[o+1] = byte val;
	return o+2;
}

put4(a: array of byte, o: int, val: int): int
{
	if(o < 0)
		return o;
	if(o + 4 > len a)
		return -o;
	a[o] = byte (val>>24);
	a[o+1] = byte (val>>16);
	a[o+2] = byte (val>>8);
	a[o+3] = byte val;
	return o+4;
}

puta(a: array of byte, o: int, b: array of byte): int
{
	if(o < 0)
		return o;
	l := len b;
	if(l > 255 || o+l+1 > len a)
		return -(o+l+1);
	a[o++] = byte l;
	a[o:] = b;
	return o+len b;
}

puts(a: array of byte, o: int, s: string): int
{
	return puta(a, o, array of byte s);
}

get2(a: array of byte, o: int): (int, int)
{
	if(o < 0)
		return (0, o);
	if(o + 2 > len a)
		return (0, -o);
	val := (int a[o] << 8) | int a[o+1];
	return (val, o+2);
}

get4(a: array of byte, o: int): (int, int)
{
	if(o < 0)
		return (0, o);
	if(o + 4 > len a)
		return (0, -o);
	val := (((((int a[o] << 8)| int a[o+1]) << 8) | int a[o+2]) << 8) | int a[o+3];
	return (val, o+4);
}

gets(a: array of byte, o: int): (string, int)
{
	if(o < 0)
		return (nil, o);
	if(o+1 > len a)
		return (nil, -o);
	l := int a[o++];
	if(o+l > len a)
		return (nil, -o);
	return (string a[o:o+l], o+l);
}

putdn(a: array of byte, o: int, name: string, labs: ref Labels): int
{
	if(o < 0)
		return o;
	o0 := o;
	while(name != "") {
		n := labs.look(name);
		if(n != 0){
			o = put2(a, o, n);
			if(o < 0)
				return -o0;
			return o;
		}
		for(l := 0; l < len name && name[l] != '.'; l++)
			;
		if(o+l+1 > len a)
			return -o0;
		labs.install(name, o);
		a[o++] = byte l;
		for(i := 0; i < l; i++)
			a[o++] = byte name[i];
		for(; l < len name && name[l] == '.'; l++)
			;
		name = name[l:];
	}
	if(o >= len a)
		return -o0;
	a[o++] = byte 0;
	return o;
}

getdn(a: array of byte, o: int, depth: int): (string, int)
{
	if(depth > 30)
		return (nil, -o);
	if(o < 0)
		return (nil, o);
	name := "";
	while(o < len a && (l := int a[o++]) != 0) {
		if((l & 16rC0) == 16rC0) {		# pointer
			if(o >= len a)
				return (nil, -o);
			po := ((l & 16r3F)<<8) | int a[o];
			if(po >= len a)
				return ("", -o);
			o++;
			pname: string;
			(pname, po) = getdn(a, po, depth+1);
			if(po < 1)
				return (nil, -o);
			name += pname;
			break;
		}
		if((l & 16rC0) != 0)
			return (nil, -o);	# format error
		if(o + l > len a)
			return (nil, -o);
		name += string a[o:o+l];
		o += l;
		if(o < len a && a[o] != byte 0)
			name += ".";
	}
	return (lower(name), o);
}

putqrl(a: array of byte, o: int, qrl: list of ref QR, labs: ref Labels): int
{
	for(; qrl != nil && o >= 0; qrl = tl qrl){
		q := hd qrl;
		o = putdn(a, o, q.name, labs);
		o = put2(a, o, q.rtype);
		o = put2(a, o, q.class);
	}
	return o;
}

getqrl(nq: int, a: array of byte, o: int): (list of ref QR, int)
{
	if(o < 0)
		return (nil, o);
	qrl: list of ref QR;
	for(i := 0; i < nq; i++) {
		qd := ref QR;
		(qd.name, o) = getdn(a, o, 0);
		(qd.rtype, o) = get2(a, o);
		(qd.class, o) = get2(a, o);
		if(o < 1)
			break;
		qrl = qd :: qrl;
	}
	q: list of ref QR;
	for(; qrl != nil; qrl = tl qrl)
		q = hd qrl :: q;
	return (q, o);
}

putrrl(a: array of byte, o: int, rrl: list of ref RR, labs: ref Labels): int
{
	if(o < 0)
		return o;
	for(; rrl != nil; rrl = tl rrl){
		rr := hd rrl;
		o0 := o;
		o = putdn(a, o, rr.name, labs);
		o = put2(a, o, rr.rtype);
		o = put2(a, o, rr.class);
		o = put4(a, o, rr.ttl);
		pick ar := rr {
		Host =>
			o = putdn(a, o, ar.host, labs);
		Hinfo =>
			o = puts(a, o, ar.cpu);
			o = puts(a, o, ar.os);
		Mx =>
			o = put2(a, o, ar.pref);
			o = putdn(a, o, ar.host, labs);
		Soa =>
			soa := ar.soa;
			o = putdn(a, o, soa.mname, labs);
			o = putdn(a, o, soa.rname, labs);
			o = put4(a, o, soa.serial);
			o = put4(a, o, soa.refresh);
			o = put4(a, o, soa.retry);
			o = put4(a, o, soa.expire);
			o = put4(a, o, soa.minttl);
		A or
		Other =>
			dlen := len ar.rdata;
			o = put2(a, o, dlen);
			if(o < 1)
				return -o0;
			if(o + dlen > len a)
				return -o0;
			a[o:] = ar.rdata;
			o += dlen;
		}
	}
	return o;
}

getrrl(nr: int, a: array of byte, o: int): (list of ref RR, int)
{
	if(o < 0)
		return (nil, o);
	rrl: list of ref RR;
	for(i := 0; i < nr; i++) {
		name: string;
		rtype, rclass, ttl: int;
		(name, o) = getdn(a, o, 0);
		(rtype, o) = get2(a, o);
		(rclass, o) = get2(a, o);
		(ttl, o) = get4(a, o);
		if(ttl <= 0)
			ttl = 0;
		#ttl = 1*60;
		ttl += now;
		dlen: int;
		(dlen, o) = get2(a, o);
		if(o < 1)
			return (rrl, o);
		if(o+dlen > len a)
			return (rrl, -(o+dlen));
		rr: ref RR;
		dname: string;
		case rtype {
		Tsoa =>
			soa := ref SOA;
			(soa.mname, o) = getdn(a, o, 0);
			(soa.rname, o) = getdn(a, o, 0);
			(soa.serial, o) = get4(a, o);
			(soa.refresh, o) = get4(a, o);
			(soa.retry, o) = get4(a, o);
			(soa.expire, o) = get4(a, o);
			(soa.minttl, o) = get4(a, o);
			rr = ref RR.Soa(name, rtype, rclass, ttl, 0, soa);
		Thinfo =>
			cpu, os: string;
			(cpu, o) = gets(a, o);
			(os, o) = gets(a, o);
			rr = ref RR.Hinfo(name, rtype, rclass, ttl, 0, cpu, os);
		Tmx =>
			pref: int;
			host: string;
			(pref, o) = get2(a, o);
			(host, o) = getdn(a, o, 0);
			rr = ref RR.Mx(name, rtype, rclass, ttl, 0, pref, host);
		Tcname or
		Tns or
		Tptr =>
			(dname, o) = getdn(a, o, 0);
			rr = ref RR.Host(name, rtype, rclass, ttl, 0, dname);
		Ta =>
			rdata := array[dlen] of byte;
			rdata[0:] = a[o:o+dlen];
			rr = ref RR.A(name, rtype, rclass, ttl, 0, rdata);
			o += dlen;
		* =>
			rdata := array[dlen] of byte;
			rdata[0:] = a[o:o+dlen];
			rr = ref RR.Other(name, rtype, rclass, ttl, 0, rdata);
			o += dlen;
		}
		rrl = rr :: rrl;
	}
	r: list of ref RR;
	for(; rrl != nil; rrl = tl rrl)
		r = (hd rrl) :: r;
	return (r, o);
}

DNSmsg.pack(msg: self ref DNSmsg, hdrlen: int): array of byte
{
	a := array[Udpdnslim+hdrlen] of byte;

	l := hdrlen;
	l = put2(a, l, msg.id);
	l = put2(a, l, msg.flags);
	l = put2(a, l, len msg.qd);
	l = put2(a, l, len msg.an);
	l = put2(a, l, len msg.ns);
	l = put2(a, l, len msg.ar);
	labs := Labels.new();
	l = putqrl(a, l, msg.qd, labs);
	l = putrrl(a, l, msg.an, labs);
	l = putrrl(a, l, msg.ns, labs);
	l = putrrl(a, l, msg.ar, labs);
	if(l < 1)
		return nil;
	return a[0:l];
}

DNSmsg.unpack(a: array of byte): ref DNSmsg
{
	msg := ref DNSmsg;
	msg.flags = Rformat;
	l := 0;
	(msg.id, l) = get2(a, l);
	(msg.flags, l) = get2(a, l);
	if(l < 0 || l > len a){
		msg.err = "length error";
		return msg;
	}
	if(l >= len a)
		return msg;

	nqd, nan, nns, nar: int;
	(nqd, l) = get2(a, l);
	(nan, l) = get2(a, l);
	(nns, l) = get2(a, l);
	(nar, l) = get2(a, l);
	if(l >= len a)
		return msg;
	(msg.qd, l) = getqrl(nqd, a, l);
	(msg.an, l) = getrrl(nan, a, l);
	(msg.ns, l) = getrrl(nns, a, l);
	(msg.ar, l) = getrrl(nar, a, l);
	if(l < 1){
		sys->fprint(stderr, "l=%d format error\n", l);
		msg.err = "format error";
		return msg;
	}
	return msg;
}

DNSmsg.text(msg: self ref DNSmsg): string
{
	s := sys->sprint("id=%ud flags=#%ux[%s]\n", msg.id, msg.flags, flagtext(msg.flags));
	s += "  QR:\n";
	for(x := msg.qd; x != nil; x = tl x)
		s += "\t"+(hd x).text()+"\n";
	s += "  AN:\n";
	for(l := msg.an; l != nil; l = tl l)
		s += "\t"+(hd l).text()+"\n";
	s += "  NS:\n";
	for(l = msg.ns; l != nil; l = tl l)
		s += "\t"+(hd l).text()+"\n";
	s += "  AR:\n";
	for(l = msg.ar; l != nil; l = tl l)
		s += "\t"+(hd l).text()+"\n";
	return s;
}

flagtext(f: int): string
{
	s := "";
	if(f & Fresp)
		s += "R";
	if(f & Fauth)
		s += "A";
	if(f & Ftrunc)
		s += "T";
	if(f & Frecurse)
		s += "r";
	if(f & Fcanrecurse)
		s += "c";
	if((f & Fresp) == 0)
		return s;
	if(s != "")
		s += ",";
	return s+reason(f & Rmask);
}

rcodes := array[] of {
	Rok => "no error",
	Rformat => "format error",
	Rserver => "server failure",
	Rname => "name does not exist",
	Runimplemented => "unimplemented",
	Rrefused => "refused",
};

reason(n: int): string
{
	if(n < 0 || n > len rcodes)
		return sys->sprint("error %d", n);
	return rcodes[n];
}

rrtype(s: string): int
{
	case s {
	"ip" => return Ta;
	"ns" => return Tns;
	"cname" => return Tcname;
	"soa" => return Tsoa;
	"ptr" => return Tptr;
	"mx" => return Tmx;
	"hinfo" => return Thinfo;
	"all" or "any" => return Tall;
	* => return -1;
	}
}

rrtypename(t: int): string
{
	case t {
	Ta =>	return "ip";
	Tns =>	return "ns";
	Tcname =>	return "cname";
	Tsoa =>	return "soa";
	Tptr =>	return "ptr";
	Tmx =>	return "mx";
	Tall =>	return "all";
	Thinfo =>	return "hinfo";
	* =>		return string t;
	}
}

#
# format of UDP head read and written in `headers' mode
#
Udphdrsize: con Udphdrlen;
dnsid := 1;

mkquery(qtype: int, qclass: int, name: string): (int, array of byte, string)
{
	qd := ref QR(name, qtype, qclass);
	dm := ref DNSmsg;
	dm.id = dnsid++;	# doesn't matter if two different procs use it
	dm.flags = Oquery;
	if(referdns || !debug)
		dm.flags |= Frecurse;
	dm.qd = qd :: nil;
	a: array of byte;
	a = dm.pack(Udphdrsize);
	if(a == nil)
		return (0, nil, "dns: bad query message");	# should only happen if a name is ridiculous
	for(i:=0; i<Udphdrsize; i++)
		a[i] = byte 0;
	a[Udprport] = byte (DNSport>>8);
	a[Udprport+1] = byte DNSport;
	return (dm.id, a, nil);
}

udpquery(fd: ref Sys->FD, id: int, query: array of byte, sname: string, addr: ref RR): (ref DNSmsg, string)
{
	# TO DO: check address and ports?

	if(debug)
		sys->print("udp query %s\n", sname);
	pick ar := addr {
	A =>
		query[Udpraddr:] = ip->v4prefix[0:IPv4off];
		query[Udpraddr+IPv4off:] = ar.rdata[0:4];
	* =>
		return (nil, "not A resource");
	}
	dm: ref DNSmsg;
	pidc := chan of int;
	c := chan of array of byte;
	spawn reader(fd, c, pidc);
	rpid := <-pidc;
	spawn timer(c, pidc);
	tpid := <-pidc;
	for(ntries := 0; ntries < 8; ntries++){
		if(debug){
			ipa := query[Udpraddr+IPv4off:];
			sys->print("send udp!%d.%d.%d.%d!%d [%d] %d\n", int ipa[0], int ipa[1],
				int ipa[2], int ipa[3], get2(query, Udprport).t0, ntries, len query);
		}
		n := sys->write(fd, query, len query);
		if(n != len query)
			return (nil, sys->sprint("udp write err: %r"));
		buf := <-c;
		if(buf != nil){
			buf = buf[Udphdrsize:];
			dm = DNSmsg.unpack(buf);
			if(dm == nil){
				kill(tpid);
				kill(rpid);
				return (nil, "bad udp reply message");
			}
			if(dm.flags & Fresp && dm.id == id){
				if(dm.flags & Ftrunc && dm.ns == nil){
					if(debug)
						sys->print("id=%d was truncated\n", dm.id);
				}else
					break;
			}else if(debug)
				sys->print("id=%d got flags #%ux id %d\n", id, dm.flags, dm.id);
		}else if(debug)
			sys->print("timeout\n");
	}
	kill(tpid);
	kill(rpid);
	if(dm == nil)
		return (nil, "no reply");
	if(dm.err != nil){
		sys->fprint(stderr, "bad reply: %s\n", dm.err);
		return (nil, dm.err);
	}
	if(debug)
		sys->print("reply: %s\n", dm.text());
	return (dm, nil);
}

reader(fd: ref Sys->FD, c: chan of array of byte, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		buf := array[4096+Udphdrsize] of byte;
		n := sys->read(fd, buf, len buf);
		if(n > 0){
			if(debug)
				sys->print("rcvd %d\n", n);
			c <-= buf[0:n];
		}else
			c <-= nil;
	}
}

timer(c: chan of array of byte, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		sys->sleep(5*1000);
		c <-= nil;
	}
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}

udpport(): ref Sys->FD
{
	(ok, conn) := sys->announce(mntpt+"/udp!*!0");
	if(ok < 0)
		return nil;
	if(sys->fprint(conn.cfd, "headers") < 0){
		sys->fprint(stderr, "dns: can't set headers mode: %r\n");
		return nil;
	}
	conn.dfd = sys->open(conn.dir+"/data", Sys->ORDWR);
	if(conn.dfd == nil){
		sys->fprint(stderr, "dns: can't open %s/data: %r\n", conn.dir);
		return nil;
	}
	return conn.dfd;
}

#
# TCP/IP can be used to get the whole of a truncated message
#
tcpquery(query: array of byte): (ref DNSmsg, string)
{
	# TO DO: check request id, ports etc.

	ipa := query[Udpraddr+IPv4off:];
	addr := sys->sprint("tcp!%d.%d.%d.%d!%d", int ipa[0], int ipa[1], int ipa[2], int ipa[3], DNSport);
	(ok, conn) := sys->dial(addr, nil);
	if(ok < 0)
		return (nil, sys->sprint("can't dial %s: %r", addr));
	query = query[Udphdrsize-2:];
	put2(query, 0, len query-2);	# replace UDP header by message length
	n := sys->write(conn.dfd, query[Udphdrsize:], len query);
	if(n != len query)
		return (nil, sys->sprint("dns: %s: write err: %r", addr));
	buf := readn(conn.dfd, 2);	# TCP/DNS record header
	(mlen, nil) := get2(buf, 0);
	if(mlen < 2 || mlen > 16384)
		return (nil, sys->sprint("dns: %s: bad reply msg length=%d", addr, mlen));
	buf = readn(conn.dfd, mlen);
	if(buf == nil)
		return (nil, sys->sprint("dns: %s: read err: %r", addr));
	dm := DNSmsg.unpack(buf);
	if(dm == nil)
		return (nil, "dns: bad reply message");
	if(dm.err != nil){
		sys->fprint(stderr, "dns: %s: bad reply: %s\n", addr, dm.err);
		return (nil, dm.err);
	}
	return (dm, nil);
}

readn(fd: ref Sys->FD, nb: int): array of byte
{
	buf:= array[nb] of byte;
	for(n:=0; n<nb;){
		m := sys->read(fd, buf[n:], nb-n);
		if(m <= 0)
			return nil;
		n += m;
	}
	return buf;
}

timefd: ref Sys->FD;

time(): int
{
	if(timefd == nil){
		timefd = sys->open("/dev/time", Sys->OREAD);
		if(timefd == nil)
			return 0;
	}
	buf := array[128] of byte;
	sys->seek(timefd, big 0, 0);
	n := sys->read(timefd, buf, len buf);
	if(n < 0)
		return 0;
	return int ((big string buf[0:n]) / big 1000000);
}

parseip(s: string): array of byte
{
	(ok, a) := IPaddr.parse(s);
	if(ok < 0 || !a.isv4())
		return nil;
	return a.v4();
}
