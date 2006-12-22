implement Bootpd;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "attrdb.m";
	attrdb: Attrdb;
	Db, Dbentry: import attrdb;

include "ip.m";
	ip: IP;
	IPaddr, Udphdr: import ip;

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

siaddr: array of byte;
sysname: string;
progname := "bootpd";
net := "/net";

Udphdrsize: con IP->OUdphdrlen;

NEED_HA: con 1;
NEED_IP: con 0;
NEED_BF: con 0;
NEED_SM: con 0;
NEED_GW: con 0;
NEED_FS: con 0;
NEED_AU: con 0;

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
	ip = load IP IP->PATH;
	if(ip == nil)
		loadfail(IP->PATH);
	ip->init();
	ether = load Ether Ether->PATH;
	if(ether == nil)
		loadfail(Ether->PATH);
	ether->init();

	fname := "/services/bootp/db";
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
		'f' =>		fname = arg->earg();
		* =>		arg->usage();
		}
	args = arg->argv();
	if(args != nil)
		arg->usage();
	arg = nil;

	sys->pctl(Sys->FORKFD|Sys->FORKNS, nil);
	if(tabopen(fname))
		raise "fail: open database";

	if(!sniff && (err := dbread()) != nil)
		error(sys->sprint("error in %s: %s", fname, err));

	addr := net+"/udp!*!67";
	if(debug)
		sys->fprint(stderr, "bootp: announcing %s\n", addr);
	(ok, c) := sys->announce(addr);
	if(ok < 0)
		error(sys->sprint("can't announce %s: %r", addr));
	get_sysname();
	get_ip();

	if(sys->fprint(c.cfd, "headers") < 0)
		error(sys->sprint("can't set headers mode: %r"));
	sys->fprint(c.cfd, "oldheaders");

	if(debug)
		sys->fprint(stderr, "bootp: opening %s/data\n", c.dir);
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
	sys->fprint(stderr, "bootp: %s\n", s);
	raise "fail:error";
}

server(c: Sys->Connection)
{
	buf := array[2048] of byte;
	badread := 0;
	for(;;) {
		if(debug)
			sys->fprint(stderr, "bootp: listening for bootp requests...\n");
		n := sys->read(c.dfd, buf, len buf);
		if(n <0) {
			if (badread++ > 10)
				break;
			continue;
		}
		badread = 0;
		if(n < Udphdrsize) {
			if(debug)
				sys->fprint(stderr, "bootp: short Udphdr: %d bytes\n", n);
			continue;
		}
		hdr := Udphdr.unpack(buf, Udphdrsize);
		if(debug)
			sys->fprint(stderr, "bootp: received request from udp!%s!%d\n", hdr.raddr.text(), hdr.rport);
		if(n < Udphdrsize+300) {
			if(debug)
				sys->fprint(stderr, "bootp: short request of %d bytes\n", n - Udphdrsize);
			continue;
		}

		(err, bootp) := M2S(buf[Udphdrsize:]);
		if(err != nil) {
			if(debug)
				sys->fprint(stderr, "bootp: M2S failed: %s\n", err);
			continue;
		}
		if(debug >= 2)
			ppkt(bootp);
		if(sniff)
			continue;
		if(bootp.htype != byte 1 || bootp.hlen != byte 6) {
			# if it isn't ether, we don't do it
			if(debug)
				sys->fprint(stderr, "bootp: hardware type not ether; ignoring.\n");
			continue;
		}
		if((err = dbread()) != nil) {
			sys->fprint(stderr,  "bootp: getreply: dbread failed: %s\n", err);
			continue;
		}
		rec := lookup(bootp);
		if(rec == nil) {
			# we can't answer this request
			if(debug)
				sys->fprint(stderr, "bootp: cannot answer request.\n");
			continue;
		}
		if(debug){
			sys->fprint(stderr, "bootp: found a matching entry:\n");
			pinfbp(rec);
		}
		mkreply(bootp, rec);
		if(verbose) sys->print("bootp: %s -> %s %s\n", ether->text(rec.ha), rec.hostname, iptoa(rec.ip));
		if(debug >= 2) {
			sys->fprint(stderr, "bootp: reply message:\n");
			ppkt(bootp);
		}
		repl:= S2M(bootp);

		if(debug)
			sys->fprint(stderr, "bootp: sending reply.\n");
		arpenter(iptoa(rec.ip), ether->text(rec.ha));
		send(repl);
	}
	sys->fprint(stderr, "bootp: %d read errors: %r\n", badread);
}

arpenter(ip, ha: string)
{
	if(debug) sys->fprint(stderr, "bootp: arp: %s -> %s\n", ip, ha);
	fd := sys->open(net+"/arp", Sys->OWRITE);
	if(fd == nil) {
		if(debug)
			sys->fprint(stderr, "bootp: arp open failed: %r\n");
		return;
	}
	if(sys->fprint(fd, "add %s %s", ip, ha) < 0){
		if(debug)
			sys->fprint(stderr, "bootp: error writing arp: %r\n");
	}
}

get_sysname()
{
	fd := sys->open("/dev/sysname", sys->OREAD);
	if(fd == nil) {
		sysname = "anon";
		return;
	}
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0) {
		sysname = "anon";
		return;
	}
	sysname = string buf[0:n];
}

get_ip()
{
	siaddr = array[4] of { * => byte 0 };
	# get a local IP address by translating our sysname with cs(8)
	fd := sys->open(net+"/cs", Sys->ORDWR);
	if(fd == nil){
		if(debug)
			sys->fprint(stderr, "bootp: cannot open %s/cs for reading: %r.\n", net);
		return;
	}
	if(sys->fprint(fd, "net!%s!0", sysname) < 0){
		if(debug)
			sys->fprint(stderr, "bootp: can't translate net!%s!0 via %s/cs: %r\n", sysname, net);
		return;
	}
	sys->seek(fd, big 0, 0);
	a := array[1024] of byte;
	n := sys->read(fd, a, len a);
	if(n < 0) {
		if(debug) sys->fprint(stderr, "bootp: read from /net/cs: %r.\n");
		return;
	}
	reply := string a[0:n];
	if(debug) sys->fprint(stderr, "bootp: read %s from /net/cs\n", reply);

	(l, addr):= sys->tokenize(reply, " ");
	if(l != 2) {
		if(debug) sys->fprint(stderr, "bootp: bad format from cs\n");
		return;
	}
	(l, addr) = sys->tokenize(hd tl addr, "!");
	if(l < 2) {
		if(debug) sys->fprint(stderr, "bootp: short addr from cs\n");
		return;
	}
	err:= "";
	(err, siaddr) = get_ipaddr(hd addr);
	if(err != nil || siaddr == nil) {
		if(debug) sys->fprint(stderr, "bootp: invalid local IP addr %s.\n", hd tl addr);
		siaddr = array[4] of { * => byte 0 };
	};
	if(debug) sys->fprint(stderr, "bootp: local IP address is %s.\n", iptoa(siaddr));
}

#	byte	op;		/* opcode */
#	byte	htype;		/* hardware type */
#	byte	hlen;		/* hardware address len */
#	byte	hops;		/* hops */
#	byte	xid[4];		/* a random number */
#	byte	secs[2];	/* elapsed snce client started booting */
#	byte	pad[2];
#	byte	ciaddr[4];	/* client IP address (client tells server) */
#	byte	yiaddr[4];	/* client IP address (server tells client) */
#	byte	siaddr[4];	/* server IP address */
#	byte	giaddr[4];	/* gateway IP address */
#	byte	chaddr[16];	/* client hardware address */
#	byte	sname[64];	/* server host name (optional) */
#	byte	file[128];	/* boot file name */
#	byte	vend[128];	/* vendor-specific goo */

BootpPKT: adt
{
	op:	byte;		# Start of udp datagram
	htype:	byte;
	hlen:	byte;
	hops:	byte;
	xid:	int;
	secs:	int;
	ciaddr:	array of byte;
	yiaddr:	array of byte;
	siaddr:	array of byte;
	giaddr:	array of byte;
	chaddr:	array of byte;
	sname:	string;
	file:	string;
	vend:	array of byte;
};

InfBP: adt {
	hostname: string;

	ha: array of byte;	# hardware addr
	ip: array of byte;	# client IP addr
	bf: array of byte;	# boot file path
	sm: array of byte;	# subnet mask
	gw: array of byte;	# gateway IP addr
	fs: array of byte;	# file server IP addr
	au: array of byte;	# authentication server IP addr
};

records: array of ref InfBP;

tabbio: ref Bufio->Iobuf;
tabname: string;
mtime: int;

tabopen(fname: string): int
{
	if(sniff) return 0;
	tabname = fname;
	if((tabbio = bufio->open(tabname, bufio->OREAD)) == nil) {
		sys->fprint(stderr, "bootp: cannot open %s: %r\n", tabname);
		return 1;
	}
	return 0;
}

send(msg: array of byte)
{
	if(debug) sys->fprint(stderr, "bootp: dialing udp!broadcast!68\n");
	(n, c) := sys->dial(net+"/udp!255.255.255.255!68", "67");
#	(n, c) := sys->dial(net+"/udp!255.255.255.255!68", "192.168.129.1!67");
	if(n < 0) {
		sys->fprint(stderr, "bootp: send: error calling dial: %r\n");
		return;
	}
	if(debug) sys->fprint(stderr, "bootp: writing to %s/data\n", c.dir);
	n = sys->write(c.dfd, msg, len msg);
	if(n <=0) {
		sys->fprint(stderr, "bootp: send: error writing to %s/data: %r\n", c.dir);
		return;
	}
	if(debug) sys->fprint(stderr, "bootp: successfully wrote %d bytes to %s/data\n", n, c.dir);
}

mkreply(bootp: ref BootpPKT, rec: ref InfBP)
{
	bootp.op = byte 2; # boot reply
	bootp.yiaddr = rec.ip;
	bootp.siaddr = siaddr;
	bootp.giaddr = array[4] of { * => byte 0 };
	bootp.sname = sysname;
	bootp.file = string rec.bf;
	bootp.vend = array of byte sys->sprint("p9  %s %s %s %s", iptoa(rec.sm), iptoa(rec.fs), iptoa(rec.au), iptoa(rec.gw));
}

lookup(bootp: ref BootpPKT): ref InfBP
{
	for(i := 0; i < len records; i++)
		if(eqa(bootp.chaddr[0:6], records[i].ha) || eqa(bootp.ciaddr, records[i].ip))
			return records[i];
	return nil;
}

dbread(): string
{
	(n, dir) := sys->fstat(tabbio.fd);
	if(n < 0)
		return sys->sprint("cannot fstat %s: %r", tabname);
	if(mtime == 0 || mtime != dir.mtime) {
		if(bufio->tabbio.seek(big 0, Sys->SEEKSTART) < big 0)
			return sys->sprint("error seeking to start of %s.", tabname);
		mtime = dir.mtime;
		lnum: int = 0;
		trecs: list of ref InfBP;
LINES:	while((line := bufio->tabbio.gets('\n')) != nil) {
			lnum++;
			if(line[0] == '#')	# comment
				continue LINES;
			fields: list of string;
			(n, fields) = sys->tokenize(line, ":\r\n");
			if(n <= 0) {	# blank line or colons
				if(len line > 0) {
					sys->fprint(stderr, "bootp: %s: %d empty entry.\n", tabname, lnum);
				}
				continue LINES;
			}
			rec := ref InfBP;
			rec.hostname = hd fields;
			fields = tl fields;
			err: string;
FIELDS:		for(; fields != nil; fields = tl fields) {
				field := hd fields;
				if(len field <= len "xx=") {
					sys->fprint(stderr, "bootp: %s:%d invalid field \"%s\" in entry for %s",
						tabname, lnum, field, rec.hostname);
					continue FIELDS;
				}
				err = nil;
				case field[0:3] {
				"ha=" =>
					if(rec.ha != nil) {
						sys->fprint(stderr,
							"bootp: warning: %s:%d hardware address redefined for %s.\n",
							tabname, lnum, rec.hostname);
					}
					(err, rec.ha) = get_haddr(field[3:]);
				"ip=" =>
					if(rec.ip != nil) {
						sys->fprint(stderr, "bootp: warning: %s:%d IP address redefined for %s.\n",
							tabname, lnum, rec.hostname);
					}
					(err, rec.ip) = get_ipaddr(field[3:]);
				"bf=" =>
					if(rec.bf != nil) {
						sys->fprint(stderr, "bootp: warning: %s:%d bootfile redefined for %s.\n",
							tabname, lnum, rec.hostname);
					}
					(err, rec.bf) = get_path(field[3:]);
				"sm=" =>
					if(rec.sm != nil) {
						sys->fprint(stderr, "bootp: warning: %s:%d subnet mask redefined for %s.\n",
							tabname, lnum, rec.hostname);
					}
					(err, rec.sm) = get_ipaddr(field[3:]);
				"gw=" =>
					if(rec.gw != nil) {
						sys->fprint(stderr, "bootp: warning: %s:%d gateway redefined for %s.\n",
							tabname, lnum, rec.hostname);
					}
					(err, rec.gw) = get_ipaddr(field[3:]);
				"fs=" =>
					if(rec.fs != nil) {
						sys->fprint(stderr, "bootp: warning: %s:%d file server redefined for %s.\n",
							tabname, lnum, rec.hostname);
					}
					(err, rec.fs) = get_ipaddr(field[3:]);
				"au=" =>
					if(rec.au != nil) {
						sys->fprint(stderr,
							"bootp: warning: %s:%d authentication server redefined for %s.\n",
							tabname, lnum, rec.hostname);
					}
					(err, rec.au) = get_ipaddr(field[3:]);
				* =>
					sys->fprint(stderr,
						"bootp: %s:%d invalid or unsupported tag \"%s\" in entry for %s.\n",
						tabname, lnum, field[0:2], rec.hostname);
					continue FIELDS;
				}
				if(err != nil) {
					sys->fprint(stderr,
						"bootp: %s:%d %s for %s.\nbootp: skipping entry for %s.\n", 
						tabname, lnum, err, rec.hostname,
						rec.hostname);
					continue LINES;
				}
			}
			if(rec.ha == nil) {
				if(NEED_HA) {
					sys->fprint(stderr, "bootp: %s:%d no hardware address defined for %s.\n",
						tabname, lnum, rec.hostname);
					sys->fprint(stderr, "bootp: skipping entry for %s.\n", rec.hostname);
					continue LINES;
				}
			}
			if(rec.ip == nil) {
				if(NEED_IP) {
					sys->fprint(stderr, "bootp: %s:%d no IP address defined for %s.\n",
						tabname, lnum, rec.hostname);
					sys->fprint(stderr, "bootp: skipping entry for %s.\n", rec.hostname);
					continue LINES;
				}
			}
			if(rec.bf == nil) {
				if(NEED_BF) {
					sys->fprint(stderr, "bootp: %s:%d no bootfile defined for %s.\n",
						tabname, lnum, rec.hostname);
					sys->fprint(stderr, "bootp: skipping entry for %s.\n", rec.hostname);
					continue LINES;
				}
			}
			if(rec.sm == nil) {
				if(NEED_SM) {
					sys->fprint(stderr, "bootp: %s:%d no subnet mask defined for %s.\n",
						tabname, lnum, rec.hostname);
					sys->fprint(stderr, "bootp: skipping entry for %s.\n", rec.hostname);
					continue LINES;
				}
			}
			if(rec.gw == nil) {
				if(NEED_GW) {
					sys->fprint(stderr, "bootp: %s:%d no gateway defined for %s.\n",
						tabname, lnum, rec.hostname);
					sys->fprint(stderr, "bootp: skipping entry for %s.\n", rec.hostname);
					continue LINES;
				}
			}
			if(rec.fs == nil) {
				if(NEED_FS) {
					sys->fprint(stderr, "bootp: %s:%d no file server defined for %s.\n",
						tabname, lnum, rec.hostname);
					sys->fprint(stderr, "bootp: skipping entry for %s.\n", rec.hostname);
					continue LINES;
				}
			}
			if(rec.au == nil) {
				if(NEED_AU) {
					sys->fprint(stderr,
						"bootp: %s:%d no authentication server defined for %s.\n",
						tabname, lnum, rec.hostname);
					sys->fprint(stderr, "bootp: skipping entry for %s.\n", rec.hostname);
					continue LINES;
				}
			}
			if(debug) pinfbp(rec);
			trecs = rec :: trecs;
		}
		if(trecs == nil) {
			sys->fprint(stderr, "bootp: no valid entries in %s.\n", tabname);
			if(records != nil) {
				sys->fprint(stderr, "bootp: reverting to previous state.\n");
				return nil;
			}
			return "no entries.";
		}
		records = array[len trecs] of ref InfBP;
		for(n = len records; n > 0; trecs = tl trecs)
			records[--n] = hd trecs;
	}
	return nil;
}

get_haddr(str: string): (string, array of byte)
{
	addr := ether->parse(str);
	if(addr == nil)
		return (sys->sprint("invalid hardware address \"%s\"", str), nil);
	return (nil, addr);
}

get_ipaddr(str: string): (string, array of byte)
{
	(ok, a) := IPaddr.parse(str);
	if(ok < 0)
		return (sys->sprint("invalid address: %s", str), nil);
	return (nil, a.v4());
}

get_path(str: string): (string, array of byte)
{
	if(str == nil) {
		return ("nil path", nil);
	}
	path := array of byte str;
	if(len path > 128)
		return (sys->sprint("path too long (>128 bytes) \"%s...\"", string path[0:16]), nil);
	return (nil, path);
}

iptoa(addr: array of byte): string
{
	if(len addr != 4)
		return "0.0.0.0";
	return sys->sprint("%d.%d.%d.%d",
		int addr[0],
		int addr[1],
		int addr[2],
		int addr[3]);
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

bptohw(bp: ref BootpPKT): string
{
	l := int bp.hlen;
	if(l > 0 && l < len bp.chaddr)
		return ether->text(bp.chaddr[0:l]);
	return "";
}

ctostr(cstr: array of byte): string
{
	for(i:=0; i<len cstr; i++)
		if(cstr[i] == byte 0)
			break;
	return string cstr[0:i];
}

strtoc(s: string): array of byte
{
	as := array of byte s;
	cs := array[1 + len as] of byte;
	cs[0:] = as;
	cs[len cs - 1] = byte 0;
	return cs;
}

ppkt(bootp: ref BootpPKT)
{
	sys->fprint(stderr, "BootpPKT {\n");
	sys->fprint(stderr, "\top == %d\n", int bootp.op);
	sys->fprint(stderr, "\thtype == %d\n", int bootp.htype);
	sys->fprint(stderr, "\thlen == %d\n", int bootp.hlen);
	sys->fprint(stderr, "\thops == %d\n", int bootp.hops);
	sys->fprint(stderr, "\txid == %d\n", bootp.xid);
	sys->fprint(stderr, "\tsecs == %d\n", bootp.secs);
	sys->fprint(stderr, "\tC client == %s\n", dtoa(bootp.ciaddr));
	sys->fprint(stderr, "\tY client == %s\n", dtoa(bootp.yiaddr));
	sys->fprint(stderr, "\tserver == %s\n", dtoa(bootp.siaddr));
	sys->fprint(stderr, "\tgateway == %s\n", dtoa(bootp.giaddr));
	sys->fprint(stderr, "\thwaddr == %s\n", bptohw(bootp));
	sys->fprint(stderr, "\thost == %s\n", bootp.sname);
	sys->fprint(stderr, "\tfile == %s\n", bootp.file);
	sys->fprint(stderr, "\tmagic == %s\n", magic(bootp.vend[0:4]));
	if(magic(bootp.vend[0:4]) == "plan9") {
		(n, strs) := sys->tokenize(string bootp.vend[4:], " \r\n");
		if(strs != nil) {
			sys->fprint(stderr, "\t\tsm == %s\n", hd strs);
			strs = tl strs;
		}
		if(strs != nil) {
			sys->fprint(stderr, "\t\tfs == %s\n", hd strs);
			strs = tl strs;
		}
		if(strs != nil) {
			sys->fprint(stderr, "\t\tau == %s\n", hd strs);
			strs = tl strs;
		}
		if(strs != nil) {
			sys->fprint(stderr, "\t\tgw == %s\n", hd strs);
			strs = tl strs;
		}
	}
	sys->fprint(stderr, "}\n\n");
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

pinfbp(rec: ref InfBP)
{
	sys->fprint(stderr, "Bootp entry {\n");
	sys->fprint(stderr, "\tha == %s\n", ether->text(rec.ha));
	sys->fprint(stderr, "\tip == %s\n", dtoa(rec.ip));
	sys->fprint(stderr, "\tbf == %s\n", string rec.bf);
	sys->fprint(stderr, "\tsm == %s\n", dtoa(rec.sm));
	sys->fprint(stderr, "\tgw == %s\n", dtoa(rec.gw));
	sys->fprint(stderr, "\tfs == %s\n", dtoa(rec.fs));
	sys->fprint(stderr, "\tau == %s\n", dtoa(rec.au));
	sys->fprint(stderr, "}\n");
}

M2S(data: array of byte): (string, ref BootpPKT)
{
	if(len data < 300)
		return ("too short", nil);

	bootp := ref BootpPKT;

	bootp.op = data[0];
	bootp.htype = data[1];
	bootp.hlen = data[2];
	bootp.hops = data[3];
	bootp.xid = nhgetl(data[4:8]);
	bootp.secs = nhgets(data[8:10]);
	# data[10:12] unused
	bootp.ciaddr = data[12:16];
	bootp.yiaddr = data[16:20];
	bootp.siaddr = data[20:24];
	bootp.giaddr = data[24:28];
	bootp.chaddr = data[28:44];
	bootp.sname = ctostr(data[44:108]);
	bootp.file = ctostr(data[108:236]);
	bootp.vend = data[236:300];

	return (nil, bootp);
}

S2M(bootp: ref BootpPKT): array of byte
{
	data := array[364] of { * => byte 0 };

	data[0] = bootp.op;
	data[1] = bootp.htype;
	data[2] = bootp.hlen;
	data[3] = bootp.hops;
	data[4:] = nhputl(bootp.xid);
	data[8:] = nhputs(bootp.secs);
	# data[10:12] unused
	data[12:] = bootp.ciaddr;
	data[16:] = bootp.yiaddr;
	data[20:] = bootp.siaddr;
	data[24:] = bootp.giaddr;
	data[28:] = bootp.chaddr;
	data[44:] = array of byte bootp.sname;
	data[108:] = array of byte bootp.file;
	data[236:] = bootp.vend;

	return data;
}

nhgetl(data: array of byte): int
{
	return (int data[0]<<24) | (int data[1]<<16) |		
	       (int data[2]<<8) | int data[3];
}

nhgets(data: array of byte): int
{
	return (int data[0]<<8) | int data[1];
}

nhputl(value: int): array of byte
{
	return array[] of {
		byte (value >> 24),
		byte (value >> 16),
		byte (value >> 8),
		byte (value >> 0),
	};
}

nhputs(value: int): array of byte
{
	return array[] of {
		byte (value >> 8),
		byte (value >> 0),
	};
}

