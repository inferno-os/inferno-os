implement Bootpd;

#
# to do:
#	DHCP
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "attrdb.m";
	attrdb: Attrdb;
	Attr, Db, Dbentry, Tuples: import attrdb;

include "dial.m";
	dial: Dial;

include "ip.m";
	ip: IP;
	IPaddr, Udphdr: import ip;

include "ipattr.m";
	ipattr: IPattr;

include "ether.m";
	ether: Ether;

include "arg.m";

Bootpd: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;
debug: int;
sniff: int;
verbose: int;

siaddr: IPaddr;
netmask: IPaddr;
myname: string;
progname := "bootpd";
net := "/net";
ndb: ref Db;
ndbfile := "/lib/ndb/local";
mtime := 0;
testing := 0;

Udphdrsize: con IP->Udphdrlen;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		loadfail(Bufio->PATH);
	attrdb = load Attrdb Attrdb->PATH;
	if(attrdb == nil)
		loadfail(Attrdb->PATH);
	attrdb->init();
	dial = load Dial Dial->PATH;
	if(dial == nil)
		loadfail(Dial->PATH);
	ip = load IP IP->PATH;
	if(ip == nil)
		loadfail(IP->PATH);
	ip->init();
	ipattr = load IPattr IPattr->PATH;
	if(ipattr == nil)
		loadfail(IPattr->PATH);
	ipattr->init(attrdb, ip);
	ether = load Ether Ether->PATH;
	if(ether == nil)
		loadfail(Ether->PATH);
	ether->init();

	verbose = 1;
	sniff = 0;
	debug = 0;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		raise "fail: load Arg";
	arg->init(args);
	arg->setusage("bootpd [-dsqv] [-f file] [-x network]");
	progname = arg->progname();
	while((o := arg->opt()) != 0)
		case o {
		'd' =>	debug++;
		's' =>		sniff = 1; debug = 255;
		'q' =>	verbose = 0;
		'v' =>	verbose = 1;
		'x' =>	net = arg->earg();
		'f' =>		ndbfile = arg->earg();
		't' =>		testing = 1; debug = 1; verbose = 1;
		* =>		arg->usage();
		}
	args = arg->argv();
	if(args != nil)
		arg->usage();
	arg = nil;

	sys->pctl(Sys->FORKFD|Sys->FORKNS, nil);

	if(!sniff && (err := dbread()) != nil)
		error(err);

	myname = sysname();
	if(myname == nil)
		error("system name not set");
	(siaddr, err) = csquery(myname);
	if(err != nil)
		error(sys->sprint("can't find IP address for %s: %s", myname, err));
	if(debug)
		sys->fprint(stderr, "bootpd: local IP address is %s\n", siaddr.text());

	addr := net+"/udp!*!67";
	if(testing)
		addr = net+"/udp!*!499";
	if(debug)
		sys->fprint(stderr, "bootpd: announcing %s\n", addr);
	c := dial->announce(addr);
	if(c == nil)
		error(sys->sprint("can't announce %s: %r", addr));
	if(sys->fprint(c.cfd, "headers") < 0)
		error(sys->sprint("can't set headers mode: %r"));

	if(debug)
		sys->fprint(stderr, "bootpd: opening %s/data\n", c.dir);
	c.dfd = sys->open(c.dir+"/data", sys->ORDWR);
	if(c.dfd == nil)
		error(sys->sprint("can't open %s/data: %r", c.dir));

	spawn server(c);
}

loadfail(s: string)
{
	error(sys->sprint("can't load %s: %r", s));
}

error(s: string)
{
	sys->fprint(stderr, "bootpd: %s\n", s);
	raise "fail:error";
}

server(c: ref Sys->Connection)
{
	buf := array[2048] of byte;
	badread := 0;
	for(;;) {
		n := sys->read(c.dfd, buf, len buf);
		if(n <0) {
			if (badread++ > 10)
				break;
			continue;
		}
		badread = 0;
		if(n < Udphdrsize) {
			if(debug)
				sys->fprint(stderr, "bootpd: short Udphdr: %d bytes\n", n);
			continue;
		}
		hdr := Udphdr.unpack(buf, Udphdrsize);
		if(debug)
			sys->fprint(stderr, "bootpd: received request from udp!%s!%d\n", hdr.raddr.text(), hdr.rport);
		if(n < Udphdrsize+300) {
			if(debug)
				sys->fprint(stderr, "bootpd: short request of %d bytes\n", n - Udphdrsize);
			continue;
		}

		(bootp, err) := Bootp.unpack(buf[Udphdrsize:]);
		if(err != nil) {
			if(debug)
				sys->fprint(stderr, "bootpd: can't unpack packet: %s\n", err);
			continue;
		}
		if(debug >= 2)
			sys->fprint(stderr, "bootpd: recvd {%s}\n", bootp.text());
		if(sniff)
			continue;
		if(bootp.htype != 1 || bootp.hlen != 6) {
			# if it isn't ether, we don't do it
			if(debug)
				sys->fprint(stderr, "bootpd: hardware type not ether; ignoring.\n");
			continue;
		}
		if((err = dbread()) != nil) {
			sys->fprint(stderr,  "bootpd: getreply: dbread failed: %s\n", err);
			continue;
		}
		rec := lookup(bootp);
		if(rec == nil) {
			# we can't answer this request
			if(debug)
				sys->fprint(stderr, "bootpd: cannot answer request.\n");
			continue;
		}
		if(debug)
			sys->fprint(stderr, "bootpd: found a matching entry: {%s}\n", rec.text());
		mkreply(bootp, rec);
		if(verbose)
			sys->print("bootpd: %s -> %s %s\n", ether->text(rec.ha), rec.hostname, rec.ip.text());
		if(debug)
			sys->fprint(stderr, "bootpd: reply {%s}\n", bootp.text());
		repl := bootp.pack();
		if(!testing)
			arpenter(rec.ip.text(), ether->text(rec.ha));
		send(hdr, repl);
	}
	sys->fprint(stderr, "bootpd: %d read errors: %r\n", badread);
}

arpenter(ip, ha: string)
{
	if(debug)
		sys->fprint(stderr, "bootpd: arp: %s -> %s\n", ip, ha);
	fd := sys->open(net+"/arp", Sys->OWRITE);
	if(fd == nil) {
		if(debug)
			sys->fprint(stderr, "bootpd: arp open failed: %r\n");
		return;
	}
	if(sys->fprint(fd, "add %s %s", ip, ha) < 0){
		if(debug)
			sys->fprint(stderr, "bootpd: error writing arp: %r\n");
	}
}

sysname(): string
{
	t := rf("/dev/sysname");
	if(t != nil)
		return t;
	return rf("#e/sysname");
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

csquery(name: string): (IPaddr, string)
{
	siaddr = ip->noaddr;
	# get a local IP address by translating our sysname with cs(8)
	csfile := net+"/cs";
	fd := sys->open(net+"/cs", Sys->ORDWR);
	if(fd == nil)
		return (ip->noaddr, sys->sprint("can't open %s/cs: %r", csfile));
	if(sys->fprint(fd, "net!%s!0", name) < 0)
		return (ip->noaddr, sys->sprint("can't translate net!%s!0: %r", name));
	sys->seek(fd, big 0, 0);
	a := array[1024] of byte;
	n := sys->read(fd, a, len a);
	if(n <= 0)
		return (ip->noaddr, "no result from "+csfile);
	reply := string a[0:n];
	(l, addr):= sys->tokenize(reply, " ");
	if(l != 2)
		return (ip->noaddr, "bad cs reply format");
	(l, addr) = sys->tokenize(hd tl addr, "!");
	if(l < 2)
		return (ip->noaddr, "bad cs reply format");
	(ok, ipa) := IPaddr.parse(hd addr);
	if(ok < 0 || !ipok(siaddr))
		return (ip->noaddr, "can't parse address: "+hd addr);
	return (ipa, nil);
}

Hostinfo: adt {
	hostname: string;

	ha: array of byte;	# hardware addr
	ip: IPaddr;		# client IP addr
	bootf: string;		# boot file path
	netmask: IPaddr;	# subnet mask
	ipgw: IPaddr;	# gateway IP addr
	fs: IPaddr;		# file server IP addr
	auth: IPaddr;	# authentication server IP addr

	text:	fn(inf: self ref Hostinfo): string;
};

send(hdr: ref Udphdr, msg: array of byte)
{
	replyaddr := net+"/udp!255.255.255.255!68";	# TO DO: gateway
	if(testing)
		replyaddr = sys->sprint("udp!%s!%d", hdr.raddr.text(), hdr.rport);
	lport := "67";
	if(testing)
		lport = "499";
	c := dial->dial(replyaddr, lport);
	if(c == nil) {
		sys->fprint(stderr, "bootpd: can't dial %s for reply: %r\n", replyaddr);
		return;
	}
	n := sys->write(c.dfd, msg, len msg);
	if(n != len msg)
		sys->fprint(stderr, "bootpd: udp write error: %r\n");
}

mkreply(bootp: ref Bootp, rec: ref Hostinfo)
{
	bootp.op = 2; # boot reply
	bootp.yiaddr = rec.ip;
	bootp.siaddr = siaddr;
	bootp.giaddr = ip->noaddr;
	bootp.sname = myname;
	bootp.file = string rec.bootf;
	bootp.vend = array of byte sys->sprint("p9  %s %s %s %s", rec.netmask.text(), rec.fs.text(), rec.auth.text(), rec.ipgw.text());
}

dbread(): string
{
	if(ndb == nil){
		ndb = Db.open(ndbfile);
		if(ndb == nil)
			return sys->sprint("cannot open %s: %r", ndbfile);
	}else if(ndb.changed())
		ndb.reopen();
	return nil;
}

ipok(a: IPaddr): int
{
	return a.isv4() && !(a.eq(ip->v4noaddr) || a.eq(ip->noaddr) || a.ismulticast());
}

lookup(bootp: ref Bootp): ref Hostinfo
{
	if(ndb == nil)
		return nil;
	inf: ref Hostinfo;
	hwaddr := ether->text(bootp.chaddr);
	if(ipok(bootp.ciaddr)){
		# client thinks it knows address; check match with MAC address
		ipaddr := bootp.ciaddr.text();
		ptr: ref Attrdb->Dbptr;
		for(;;){
			e: ref Dbentry;
			(e, ptr) = ndb.findbyattr(ptr, "ip", ipaddr, "ether");
			if(e == nil)
				break;
			# TO DO: check result
			inf = matchandfill(e, "ip", ipaddr, "ether", hwaddr);
			if(inf != nil)
				return inf;
		}
	}
	# look up an ip address associated with given MAC address
	ptr: ref Attrdb->Dbptr;
	for(;;){
		e: ref Dbentry;
		(e, ptr) = ndb.findbyattr(ptr, "ether", hwaddr, "ip");
		if(e == nil)
			break;
		# TO DO: check right net etc.
		inf = matchandfill(e, "ether", hwaddr, "ip", nil);
		if(inf != nil)
			return inf;
	}
	return nil;
}

matchandfill(e: ref Dbentry, attr: string, val: string, rattr: string, rval: string): ref Hostinfo
{
	matches := e.findbyattr(attr, val, rattr);
	for(; matches != nil; matches = tl matches){
		(line, attrs) := hd matches;
		for(; attrs != nil; attrs = tl attrs){
			if(rval == nil || (hd attrs).val == rval){
				inf := fillup(line, e);
				if(inf != nil)
					return inf;
				break;
			}
		}
	}
	return nil;
}

fillup(line: ref Tuples, e: ref Dbentry): ref Hostinfo
{
	ok: int;
	inf := ref Hostinfo;
	inf.netmask = ip->noaddr;
	inf.ipgw = ip->noaddr;
	inf.fs = ip->v4noaddr;
	inf.auth = ip->v4noaddr;
	inf.hostname = find(line, e, "sys");
	s := find(line, e, "ether");
	if(s != nil)
		inf.ha = ether->parse(s);
	s = find(line, e, "ip");
	if(s == nil)
		return nil;
	(ok, inf.ip) = IPaddr.parse(s);
	if(ok < 0)
		return nil;
	(results, err) := ipattr->findnetattrs(ndb, "ip", s, list of{"ipmask", "ipgw", "fs", "FILESERVER", "SIGNER", "auth", "bootf"});
	if(err != nil)
		return nil;
	for(; results != nil; results = tl results){
		(a, nattrs) := hd results;
		if(!a.eq(inf.ip))
			continue;	# different network
		for(; nattrs != nil; nattrs = tl nattrs){
			na := hd nattrs;
			case na.name {
			"ipmask" =>
				inf.netmask = takeipmask(na.pairs, inf.netmask);
			"ipgw" =>
				inf.ipgw = takeipattr(na.pairs, inf.ipgw);
			"fs" or "FILESERVER" =>
				inf.fs = takeipattr(na.pairs, inf.fs);
			"auth" or "SIGNER" =>
				inf.auth = takeipattr(na.pairs, inf.auth);
			"bootf" =>
				inf.bootf = takeattr(na.pairs, inf.bootf);
			}
		}
	}
	return inf;
}

takeattr(pairs: list of ref Attr, s: string): string
{
	if(s != nil || pairs == nil)
		return s;
	return (hd pairs).val;
}

takeipattr(pairs: list of ref Attr, a: IPaddr): IPaddr
{
	if(pairs == nil || !(a.eq(ip->noaddr) || a.eq(ip->v4noaddr)))
		return a;
	(ok, na) := parseip((hd pairs).val);
	if(ok < 0)
		return a;
	return na;
}

takeipmask(pairs: list of ref Attr, a: IPaddr): IPaddr
{
	if(pairs == nil || !(a.eq(ip->noaddr) || a.eq(ip->v4noaddr)))
		return a;
	(ok, na) := IPaddr.parsemask((hd pairs).val);
	if(ok < 0)
		return a;
	return na;
}

findip(line: ref Tuples, e: ref Dbentry, attr: string): (int, IPaddr)
{
	s := find(line, e, attr);
	if(s == nil)
		return (-1, ip->noaddr);
	return parseip(s);
}

parseip(s: string): (int, IPaddr)
{
	(ok, a) := IPaddr.parse(s);
	if(ok < 0){
		# look it up if it's a system name
		s = findbyattr("sys", s, "ip");
		(ok, a) = IPaddr.parse(s);
	}
	return (ok, a);
}

find(line: ref Tuples, e: ref Dbentry, attr: string): string
{
	if(line != nil){
		a := line.find(attr);
		if(a != nil)
			return (hd a).val;
	}
	if(e != nil){
		for(matches := e.find(attr); matches != nil; matches = tl matches){
			(nil, a) := hd matches;
			if(a != nil)
				return (hd a).val;
		}
	}
	return nil;
}

findbyattr(attr: string, val: string, rattr: string): string
{
	ptr: ref Attrdb->Dbptr;
	for(;;){
		e: ref Dbentry;
		(e, ptr) = ndb.findbyattr(ptr, attr, val, rattr);
		if(e == nil)
			break;
		rvl := e.find(rattr);
		if(rvl != nil){
			(nil, al) := hd rvl;
			return (hd al).val;
		}
	}
	return nil;
}

missing(rec: ref Hostinfo): string
{
	s := "";
	if(rec.ha == nil)
		s += " hardware address";
	if(rec.ip.eq(ip->noaddr))
		s += " IP address";
	if(rec.bootf == nil)
		s += " bootfile";
	if(rec.netmask.eq(ip->noaddr))
		s += " subnet mask";
	if(rec.ipgw.eq(ip->noaddr))
		s += " gateway";
	if(rec.fs.eq(ip->noaddr))
		s += " file server";
	if(rec.auth.eq(ip->noaddr))
		s += " authentication server";
	if(s != "")
		return s[1:];
	return nil;
}

dtoa(data: array of byte): string
{
	if(data == nil)
		return nil;
	result: string;
	for(i:=0; i < len data; i++)
		result += sys->sprint(".%d", int data[i]);
	return result[1:];
}

magic(cookie: array of byte): string
{
	if(eqa(cookie, array[] of { byte 'p', byte '9', byte ' ', byte ' ' }))
		return "plan9";
	if(eqa(cookie, array[] of { byte 99, byte 130, byte 83, byte 99 }))
		return "rfc1048";
	if(eqa(cookie, array[] of { byte 'C', byte 'M', byte 'U', byte 0 }))
		return "cmu";
	return dtoa(cookie);
}

eqa(a1: array of byte, a2: array of byte): int
{
	if(len a1 != len a2)
		return 0;
	for(i := 0; i < len a1; i++)
		if(a1[i] != a2[i])
			return 0;
	return 1;
}

Hostinfo.text(rec: self ref Hostinfo): string
{
	return sys->sprint("ha=%s ip=%s bf=%s sm=%s gw=%s fs=%s au=%s",
		ether->text(rec.ha), rec.ip.text(), rec.bootf, rec.netmask.masktext(), rec.ipgw.text(), rec.fs.text(), rec.auth.text());
}

Bootp: adt
{
	op:	int;		# opcode [1]
	htype:	int;	# hardware type[1]
	hlen:	int;		# hardware address length [1]
	hops:	int;	# gateway hops [1]
	xid:	int;		# random number [4]
	secs:	int;		# seconds elapsed since client started booting [2]
	flags:	int;	# flags[2]
	ciaddr:	IPaddr;	# client ip address (client->server)[4]
	yiaddr:	IPaddr;	# your ip address (server->client)[4]
	siaddr:	IPaddr;	# server's ip address [4]
	giaddr:	IPaddr;	# gateway ip address [4]
	chaddr:	array of byte;	# client hardware (mac) address [16]
	sname:	string;	# server host name [64]
	file:	string;		# boot file name [128]
	vend:	array of byte;	# vendor-specific [128]

	unpack:	fn(a: array of byte): (ref Bootp, string);
	pack:	fn(bp: self ref Bootp): array of byte;
	text:	fn(bp: self ref Bootp): string;
};

Bootp.unpack(data: array of byte): (ref Bootp, string)
{
	if(len data < 300)
		return (nil, "too short");

	bp := ref Bootp;
	bp.op = int data[0];
	bp.htype = int data[1];
	bp.hlen = int data[2];
	if(bp.hlen > 16)
		return (nil, "length error");
	bp.hops = int data[3];
	bp.xid = ip->get4(data, 4);
	bp.secs = ip->get2(data, 8);
	bp.flags = ip->get2(data, 10);
	bp.ciaddr = IPaddr.newv4(data[12:16]);
	bp.yiaddr = IPaddr.newv4(data[16:20]);
	bp.siaddr = IPaddr.newv4(data[20:24]);
	bp.giaddr = IPaddr.newv4(data[24:28]);
	bp.chaddr = data[28:28+bp.hlen];
	bp.sname = ctostr(data[44:108]);
	bp.file = ctostr(data[108:236]);
	bp.vend = data[236:300];
	return (bp, nil);
}

Bootp.pack(bp: self ref Bootp): array of byte
{
	data := array[364] of { * => byte 0 };
	data[0] = byte bp.op;
	data[1] = byte bp.htype;
	data[2] = byte bp.hlen;
	data[3] = byte bp.hops;
	ip->put4(data, 4, bp.xid);
	ip->put2(data, 8, bp.secs);
	ip->put2(data, 10, bp.flags);
	data[12:] = bp.ciaddr.v4();
	data[16:] = bp.yiaddr.v4();
	data[20:] = bp.siaddr.v4();
	data[24:] = bp.giaddr.v4();
	data[28:] = bp.chaddr;
	data[44:] = array of byte bp.sname;
	data[108:] = array of byte bp.file;
	data[236:] = bp.vend;
	return data;
}

ctostr(cstr: array of byte): string
{
	for(i:=0; i<len cstr; i++)
		if(cstr[i] == byte 0)
			break;
	return string cstr[0:i];
}

Bootp.text(bp: self ref Bootp): string
{
	s := sys->sprint("op=%d htype=%d hlen=%d hops=%d xid=%ud secs=%ud ciaddr=%s yiaddr=%s",
		int bp.op, bp.htype, bp.hlen, bp.hops, bp.xid, bp.secs, bp.ciaddr.text(), bp.yiaddr.text());
	s += sys->sprint(" server=%s gateway=%s hwaddr=%q host=%q file=%q magic=%q",
		bp.siaddr.text(), bp.giaddr.text(), ether->text(bp.chaddr), bp.sname, bp.file, magic(bp.vend[0:4]));
	if(magic(bp.vend[0:4]) == "plan9")
		s += "("+ctostr(bp.vend)+")";
	return s;
}
