implement Dhcpclient;

#
# DHCP and BOOTP clients
# Copyright © 2004-2006 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;

include "ip.m";
	ip: IP;
	IPv4off, IPaddrlen, Udphdrlen, Udpraddr, Udpladdr, Udprport, Udplport: import IP;
	IPaddr: import ip;
	get2, get4, put2, put4: import ip;

include "keyring.m";
include "security.m";	# for Random

include "dhcp.m";

debug := 0;

xidgen: int;

init()
{
	sys = load Sys Sys->PATH;
	random := load Random Random->PATH;
	if(random != nil)
		xidgen = random->randomint(Random->NotQuiteRandom);
	else
		xidgen = sys->pctl(0, nil)*sys->millisec();
	random = nil;
	ip = load IP IP->PATH;
	ip->init();
}

tracing(d: int)
{
	debug = d;
}

Bootconf.new(): ref Bootconf
{
	bc := ref Bootconf;
	bc.lease = 0;
	bc.options = array[256] of array of byte;
	return bc;
}

Bootconf.get(c: self ref Bootconf, n: int): array of byte
{
	a := c.options;
	if(n & Ovendor){
		a = c.vendor;
		n &= ~Ovendor;
	}
	if(n < 0 || n >= len a)
		return nil;
	return a[n];
}

Bootconf.getint(c: self ref Bootconf, n: int): int
{
	a := c.get(n);
	v := 0;
	for(i := 0; i < len a; i++)
		v = (v<<8) | int a[i];
	return v;
}

Bootconf.getip(c: self ref Bootconf, n: int): string
{
	l := c.getips(n);
	if(l == nil)
		return nil;
	return hd l;
}

Bootconf.getips(c: self ref Bootconf, n: int): list of string
{
	a := c.get(n);
	rl: list of string;
	while(len a >= 4){
		rl = v4text(a) :: rl;
		a = a[4:];
	}
	l: list of string;
	for(; rl != nil; rl = tl rl)
		l = hd rl :: l;
	return l;
}

Bootconf.gets(c: self ref Bootconf, n: int): string
{
	a := c.get(n);
	if(a == nil)
		return nil;
	for(i:=0; i<len a; i++)
		if(a[i] == byte 0)
			break;
	return string a[0:i];
}

Bootconf.put(c: self ref Bootconf, n: int, a: array of byte)
{
	if(n < 0 || n >= len c.options)
		return;
	ca := array[len a] of byte;
	ca[0:] = a;
	c.options[n] = ca;
}

Bootconf.putint(c: self ref Bootconf, n: int, v: int)
{
	if(n < 0 || n >= len c.options)
		return;
	a := array[4] of byte;
	put4(a, 0, v);
	c.options[n] = a;
}

Bootconf.putips(c: self ref Bootconf, n: int, ips: list of string)
{
	if(n < 0 || n >= len c.options)
		return;
	na := len ips;
	a := array[na*4] of byte;
	na = 0;
	for(; ips != nil; ips = tl ips){
		(nil, ipa) := IPaddr.parse(hd ips);
		a[na++:] = ipa.v4();
	}
	c.options[n] = a;
}

Bootconf.puts(c: self ref Bootconf, n: int, s: string)
{
	if(n < 0 || n >= len c.options)
		return;
	c.options[n] = array of byte s;
}

#
#
# DHCP
#
#

# BOOTP operations
Bootprequest, Bootpreply: con 1+iota;

# DHCP operations
NotDHCP, Discover, Offer, Request, Decline, Ack, Nak, Release, Inform: con iota;

Dhcp: adt {
	udphdr:	array of byte;
	op:		int;
	htype:	int;
	hops:	int;
	xid:		int;
	secs:		int;
	flags:	int;
	ciaddr:	IPaddr;
	yiaddr:	IPaddr;
	siaddr:	IPaddr;
	giaddr:	IPaddr;
	chaddr:	array of byte;
	sname:	string;
	file:		string;
	options:	list of (int, array of byte);
	dhcpop:	int;
};

opnames := array[] of {
	Discover => "Discover",
	Offer => "Offer",
	Request => "Request",
	Decline => "Decline",
	Ack => "Ack",
	Nak => "Nak",
	Release => "Release",
	Inform => "Inform"
};

opname(op: int): string
{
	if(op >= 0 && op < len opnames)
		return opnames[op];
	return sys->sprint("OP%d", op);
}

stringget(buf: array of byte): string
{
	for(x := 0; x < len buf; x++)
		if(buf[x] == byte 0)
			break;
	if(x == 0)
		return nil;
	return string buf[0 : x];
}

eqbytes(b1: array of byte, b2: array of byte): int
{
	l := len b1;
	if(l != len b2)
		return 0;
	for(i := 0; i < l; i++)
		if(b1[i] != b2[i])
			return 0;
	return 1;
}

magic := array[] of {byte 99, byte 130, byte 83, byte 99};	# RFC2132 (replacing RFC1048)

dhcpsend(fd: ref Sys->FD, xid: int, dhcp: ref Dhcp)
{
	dhcp.xid = xid;
	abuf := array[576+Udphdrlen] of {* => byte 0};
	abuf[0:] = dhcp.udphdr;
	buf := abuf[Udphdrlen:];
	buf[0] = byte dhcp.op;
	buf[1] = byte dhcp.htype;
	buf[2] = byte len dhcp.chaddr;
	buf[3] = byte dhcp.hops;
	put4(buf, 4, xid);
	put2(buf, 8, dhcp.secs);
	put2(buf, 10, dhcp.flags);
	buf[12:] = dhcp.ciaddr.v4();
	buf[16:] = dhcp.yiaddr.v4();
	buf[20:] = dhcp.siaddr.v4();
	buf[24:] = dhcp.giaddr.v4();
	buf[28:] = dhcp.chaddr;
	buf[44:] = array of byte dhcp.sname;	# [64]
	buf[108:] = array of byte dhcp.file;	# [128]
	o := 236;
	# RFC1542 suggests including magic and Oend as a minimum, even in BOOTP
	buf[o:] = magic;
	o += 4;
	if(dhcp.dhcpop != NotDHCP){
		buf[o++] = byte Otype;
		buf[o++] = byte 1;
		buf[o++] = byte dhcp.dhcpop;
	}
	for(ol := dhcp.options; ol != nil; ol = tl ol){
		(opt, val) := hd ol;
		buf[o++] = byte opt;
		buf[o++] = byte len val;
		if(len val > 0){
			buf[o:] = val;
			o += len val;
		}
	}
	buf[o++] = byte Oend;
	if(debug)
		dumpdhcp(dhcp, "->");
	sys->write(fd, abuf, len abuf);
}

kill(pid: int, grp: string)
{
	fd := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill%s", grp);
}

v4text(a: array of byte): string
{
	return sys->sprint("%ud.%ud.%ud.%ud", int a[0], int a[1], int a[2], int a[3]);
}

parseopt(a: array of byte, isdhcp: int): (int, list of (int, array of byte))
{
	opts: list of (int, array of byte);
	xop := NotDHCP;
	for(i := 0; i < len a;){
		op := int a[i++];
		if(op == Opad)
			continue;
		if(op == Oend || i >= len a)
			break;
		l := int a[i++];
		if(i+l > len a)
			break;
		if(isdhcp && op == Otype)
			xop = int a[i];
		else
			opts = (op, a[i:i+l]) :: opts;
		i += l;
	}
	rl := opts;
	opts = nil;
	for(; rl != nil; rl = tl rl)
		opts = hd rl :: opts;
	return (xop, opts);
}

dhcpreader(pidc: chan of int, srv: ref DhcpIO)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		abuf := array [576+Udphdrlen] of byte;
		n := sys->read(srv.fd, abuf, len abuf);
		if(n < 0){
			if(debug)
				sys->print("read error: %r\n");
			sys->sleep(1000);
			continue;
		}
		if(n < Udphdrlen+236){
			if(debug)
				sys->print("short read: %d\n", n);
			continue;
		}
		buf := abuf[Udphdrlen:n];
		n -= Udphdrlen;
		dhcp := ref Dhcp;
		dhcp.op = int buf[0];
		if(dhcp.op != Bootpreply){
			if(debug)
				sys->print("bootp: not reply, discarded\n");
			continue;
		}
		dhcp.dhcpop = NotDHCP;
		if(n >= 240 && eqbytes(buf[236:240], magic))	# otherwise it's something we won't understand
			(dhcp.dhcpop, dhcp.options) = parseopt(buf[240:n], 1);
		case dhcp.dhcpop {
		NotDHCP or Ack or Nak or Offer =>
			;
		* =>
			if(debug)
				sys->print("dhcp: ignore dhcp op %d\n", dhcp.dhcpop);
			continue;
		}
		dhcp.udphdr = abuf[0:Udphdrlen];
		dhcp.htype = int buf[1];
		hlen := int buf[2];
		dhcp.hops = int buf[3];
		dhcp.xid = get4(buf, 4);
		dhcp.secs = get2(buf, 8);
		dhcp.flags = get2(buf, 10);
		dhcp.ciaddr = IPaddr.newv4(buf[12:]);
		dhcp.yiaddr = IPaddr.newv4(buf[16:]);
		dhcp.siaddr = IPaddr.newv4(buf[20:]);
		dhcp.giaddr = IPaddr.newv4(buf[24:]);
		dhcp.chaddr = buf[28 : 28 + hlen];
		dhcp.sname = stringget(buf[44 : 108]);
		dhcp.file = stringget(buf[108 : 236]);
		srv.dc <-= dhcp;
	}
}

timeoutstart(msecs: int): (int, chan of int)
{
	tc := chan of int;
	spawn timeoutproc(tc, msecs);
	return (<-tc, tc);
}

timeoutproc(c: chan of int, msecs: int)
{
	c <-= sys->pctl(0, nil);
	sys->sleep(msecs);
	c <-= 1;
}

hex(b: int): int
{
	if(b >= '0' && b <= '9')
		return b-'0';
	if(b >= 'A' && b <= 'F')
		return b-'A' + 10;
	if(b >= 'a' && b <= 'f')
		return b-'a' + 10;
	return -1;
}

gethaddr(device: string): (int, string, array of byte)
{
	fd := sys->open(device, Sys->OREAD);
	if(fd == nil)
		return (-1, sys->sprint("%r"), nil);
	buf := array [100] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return (-1, sys->sprint("%r"), nil);
	if(n == 0)
		return (-1, "empty address file", nil);
	addr := array [n/2] of byte;
	for(i := 0; i < len addr; i++){
		u := hex(int buf[2*i]);
		l := hex(int buf[2*i+1]);
		if(u < 0 || l < 0)
			return (-1, "bad address syntax", nil);
		addr[i] = byte ((u<<4)|l);
	}
	return (1, nil, addr);
}

newrequest(dest: IPaddr, bootfile: string, htype: int, haddr: array of byte, ipaddr: IPaddr, options: array of array of byte): ref Dhcp
{
	dhcp := ref Dhcp;
	dhcp.op = Bootprequest;
	hdr := array[Udphdrlen] of {* => byte 0};
	hdr[Udpraddr:] = dest.v6();
	put2(hdr, Udprport, 67);
	dhcp.udphdr = hdr;
	dhcp.htype = htype;
	dhcp.chaddr = haddr;
	dhcp.hops = 0;
	dhcp.secs = 0;
	dhcp.flags = 0;
	dhcp.xid = 0;
	dhcp.ciaddr = ipaddr;
	dhcp.yiaddr = ip->v4noaddr;
	dhcp.siaddr = ip->v4noaddr;
	dhcp.giaddr = ip->v4noaddr;
	dhcp.file = bootfile;
	dhcp.dhcpop = NotDHCP;
	if(options != nil){
		for(i := 0; i < len options; i++)
			if(options[i] != nil)
				dhcp.options = (i, options[i]) :: dhcp.options;
	}
	clientid := array[len haddr + 1] of byte;
	clientid[0] = byte htype;
	clientid[1:] = haddr;
	dhcp.options = (Oclientid, clientid) :: dhcp.options;
	dhcp.options = (Ovendorclass, array of byte "plan9_386") :: dhcp.options;	# 386 will do because type doesn't matter
	return dhcp;
}

udpannounce(net: string): (ref Sys->FD, string)
{
	if(net == nil)
		net = "/net";
	(ok, conn) := sys->announce(net+"/udp!*!68");
	if(ok < 0)
		return (nil, sys->sprint("can't announce dhcp port: %r"));
	if(sys->fprint(conn.cfd, "headers") < 0)
		return (nil, sys->sprint("can't set headers mode on dhcp port: %r"));
	conn.dfd = sys->open(conn.dir+"/data", Sys->ORDWR);
	if(conn.dfd == nil)
		return (nil, sys->sprint("can't open %s: %r", conn.dir+"/data"));
	return (conn.dfd, nil);
}

ifcnoaddr(fd: ref Sys->FD, s: string)
{
	if(fd != nil && sys->fprint(fd, "%s %s %s", s, (ip->noaddr).text(), (ip->noaddr).text()) < 0){
		if(debug)
			sys->print("dhcp: ctl %s: %r\n", s);
	}
}

setup(net: string, device: string, init: ref Bootconf): (ref Dhcp, ref DhcpIO, string)
{
	(htype, err, mac) := gethaddr(device);
	if(htype < 0)
		return (nil, nil, sys->sprint("can't get hardware MAC address: %s", err));
	ciaddr := ip->v4noaddr;
	if(init != nil && init.ip != nil){
		valid: int;
		(valid, ciaddr) = IPaddr.parse(init.ip);
		if(valid < 0)
			return (nil, nil, sys->sprint("invalid ip address: %s", init.ip));
	}
	(dfd, err2) := udpannounce(net);
	if(err2 != nil)
		return (nil, nil, err);
	bootfile: string;
	options: array of array of byte;
	if(init != nil){
		bootfile = init.bootf;
		options = init.options;
	}
	return (newrequest(ip->v4bcast, bootfile, htype, mac, ciaddr, options), DhcpIO.new(dfd), nil);
}

#
# BOOTP (RFC951) is used by Inferno only during net boots, to get initial IP address and TFTP address and parameters
#
bootp(net: string, ctlifc: ref Sys->FD, device: string, init: ref Bootconf): (ref Bootconf, string)
{
	(req, srv, err) := setup(net, device, init);
	if(err != nil)
		return (nil, err);
	ifcnoaddr(ctlifc, "add");
	rdhcp := exchange(srv, ++xidgen, req, 1<<NotDHCP);
	srv.rstop();
	ifcnoaddr(ctlifc, "remove");
	if(rdhcp == nil)
		return (nil, "no response to BOOTP request");
	return (fillbootconf(init, rdhcp), nil);
}

defparams := array[] of {
	byte Omask, byte Orouter, byte Odnsserver, byte Ohostname, byte Odomainname, byte Ontpserver,
};

#
# DHCP (RFC2131)
#
dhcp(net: string, ctlifc: ref Sys->FD, device: string, init: ref Bootconf, needparam: array of int): (ref Bootconf, ref Lease, string)
{
	(req, srv, err) := setup(net, device, init);
	if(err != nil)
		return (nil, nil, err);
	params := defparams;
	if(needparam != nil){
		n := len defparams;
		params = array[n+len needparam] of byte;
		params[0:] = defparams;
		for(i := 0; i < len needparam; i++)
			params[n+i] = byte needparam[i];
	}
	initopt := (Oparams, params) :: req.options;	# RFC2131 requires parameters to be repeated each time
	lease := ref Lease(0, chan[1] of (ref Bootconf, string));
	spawn dhcp1(srv, lease, net, ctlifc, req, init, initopt);
	bc: ref Bootconf;
	(bc, err) = <-lease.configs;
	return (bc, lease, err);
}

dhcp1(srv: ref DhcpIO, lease: ref Lease, net: string, ctlifc: ref Sys->FD, req: ref Dhcp, init: ref Bootconf, initopt: list of (int, array of byte))
{
	cfd := -1;
	if(ctlifc != nil)
		cfd = ctlifc.fd;
	lease.pid = sys->pctl(Sys->NEWPGRP|Sys->NEWFD, 1 :: srv.fd.fd :: cfd :: nil);
	if(ctlifc != nil)
		ctlifc = sys->fildes(ctlifc.fd);
	srv.fd = sys->fildes(srv.fd.fd);
	rep: ref Dhcp;
	ifcnoaddr(ctlifc, "add");
	if(req.ciaddr.isvalid())
		rep = reacquire(srv, req, initopt, req.ciaddr);
	if(rep == nil)
		rep = askround(srv, req, initopt);
	srv.rstop();
	ifcnoaddr(ctlifc, "remove");
	if(rep == nil){
		lease.pid = 0;
		lease.configs <-= (nil, "no response");
		exit;
	}
	for(;;){
		conf := fillbootconf(init, rep);
		applycfg(net, ctlifc, conf);
		if(conf.lease == 0){
			srv.rstop();
			lease.pid = 0;
			flush(lease.configs);
			lease.configs <-= (conf, nil);
			exit;
		}
		flush(lease.configs);
		lease.configs <-= (conf, nil);
		req.ciaddr = rep.yiaddr;
		while((rep = tenancy(srv, req, conf.lease)) != nil){
			if(rep.dhcpop == Nak || !rep.ciaddr.eq(req.ciaddr))
				break;
			req.udphdr[Udpraddr:] = rep.udphdr[Udpraddr:Udpraddr+IPaddrlen];
			conf = fillbootconf(init, rep);
		}
		removecfg(net, ctlifc, conf);
		ifcnoaddr(ctlifc, "add");
		while((rep = askround(srv, req, initopt)) == nil){
			flush(lease.configs);
			lease.configs <-= (nil, "no response");
			srv.rstop();
			sys->sleep(60*1000);
		}
		ifcnoaddr(ctlifc, "remove");
	}
}

reacquire(srv: ref DhcpIO, req: ref Dhcp, initopt: list of (int, array of byte), addr: IPaddr): ref Dhcp
{
	# INIT-REBOOT: know an address; try requesting it (once)
	# TO DO: could use Inform when our address is static but we need a few service parameters
	req.ciaddr = ip->v4noaddr;
	rep := request(srv, ++xidgen, req, (Oipaddr, addr.v4()) :: initopt);
	if(rep != nil && rep.dhcpop == Ack && addr.eq(rep.yiaddr)){
		if(debug)
			sys->print("req: server accepted\n");
		req.udphdr[Udpraddr:] = rep.udphdr[Udpraddr:Udpraddr+IPaddrlen];
		return rep;
	}
	if(debug)
		sys->print("req: cannot reclaim\n");
	return nil;
}

askround(srv: ref DhcpIO, req: ref Dhcp, initopt: list of (int, array of byte)): ref Dhcp
{
	# INIT
	req.ciaddr = ip->v4noaddr;
	req.udphdr[Udpraddr:] = (ip->v4bcast).v6();
	for(retries := 0; retries < 5; retries++){
		# SELECTING
		req.dhcpop = Discover;
		req.options = initopt;
		rep := exchange(srv, ++xidgen, req, 1<<Offer);
		if(rep == nil)
			break;
		#
		# could wait a little while and accumulate offers, but is it sensible?
		# we do sometimes see arguments between DHCP servers that could
		# only be resolved by user choice
		#
		if(!rep.yiaddr.isvalid())
			continue;		# server has no idea either
		serverid := getopt(rep.options, Oserverid, 4);
		if(serverid == nil)
			continue;	# broken server
		# REQUESTING
		options := (Oserverid, serverid) :: (Oipaddr, rep.yiaddr.v4()) :: initopt;
		lease := getlease(rep);
		if(lease != nil)
			options = (Olease, lease) :: options;
		rep = request(srv, rep.xid, req, options);
		if(rep != nil){
			# could probe with ARP here, and if found, Decline
			if(debug)
				sys->print("req: server accepted\n");
			req.udphdr[Udpraddr:] = rep.udphdr[Udpraddr:Udpraddr+IPaddrlen];
			return rep;
		}
	}
	return nil;
}

request(srv: ref DhcpIO, xid: int, req: ref Dhcp, options: list of (int, array of byte)): ref Dhcp
{
	req.dhcpop = Request;	# Selecting
	req.options = options;
	rep := exchange(srv, xid, req, (1<<Ack)|(1<<Nak));
	if(rep == nil || rep.dhcpop == Nak)
		return nil;
	return rep;
}

# renew
#	direct to server from T1 to T2 [RENEW]
#	Request must not include
#		requested IP address, server identifier
#	Request must include
#		ciaddr set to client's address
#	Request might include
#		lease time
#	similar, but broadcast, from T2 to T3 [REBIND]
#	at T3, unbind, restart Discover

tenancy(srv: ref DhcpIO, req: ref Dhcp, leasesec: int): ref Dhcp
{
	# configure address...
	t3 := big leasesec * big 1000;	# lease expires; restart
	t2 := (big 3 * t3)/big 4;	# broadcast renewal request at ¾time
	t1 := t2/big 2;		# renew lease with original server at ½time
	srv.rstop();
	thebigsleep(t1);
	# RENEW
	rep := renewing(srv, req, t1, t2);
	if(rep != nil)
		return rep;
	# REBIND
	req.udphdr[Udpraddr:] = (ip->v4bcast).v6();	# now try broadcast
	return renewing(srv, req, t2, t3);
}

renewing(srv: ref DhcpIO, req: ref Dhcp, a: big, b: big): ref Dhcp
{
	Minute: con big(60*1000);
	while(a < b){
		rep := exchange(srv, req.xid, req, (1<<Ack)|(1<<Nak));
		if(rep != nil)
			return rep;
		delta := (b-a)/big 2;
		if(delta < Minute)
			delta = Minute;
		thebigsleep(delta);
		a += delta;
	}
	return nil;
}

thebigsleep(msec: big)
{
	Day: con big (24*3600*1000);	# 1 day in msec
	while(msec > big 0){
		n := msec;
		if(n > Day)
			n = Day;
		sys->sleep(int n);
		msec -= n;
	}
}

getlease(m: ref Dhcp): array of byte
{
	lease := getopt(m.options, Olease, 4);
	if(lease == nil)
		return nil;
	if(get4(lease, 0) == 0){
		lease = array[4] of byte;
		put4(lease, 0, 15*60);
	}
	return lease;
}

fillbootconf(init: ref Bootconf, pkt: ref Dhcp): ref Bootconf
{
	bc := ref Bootconf;
	if(init != nil)
		*bc = *init;
	if(bc.options == nil)
		bc.options = array[256] of array of byte;
	for(l := pkt.options; l != nil; l = tl l){
		(c, v) := hd l;
		if(bc.options[c] == nil)
			bc.options[c] = v;	# give priority to first occurring
	}
	if((a := bc.get(Ovendorinfo)) != nil){
		if(bc.vendor == nil)
			bc.vendor = array[256] of array of byte;
		for(l = parseopt(a, 0).t1; l  != nil; l = tl l){
			(c, v) := hd l;
			if(bc.vendor[c] == nil)
				bc.vendor[c] = v;
		}
	}
	if(pkt.yiaddr.isvalid()){
		bc.ip = pkt.yiaddr.text();
		bc.ipmask = bc.getip(Omask);
		if(bc.ipmask == nil)
			bc.ipmask = pkt.yiaddr.classmask().masktext();
	}
	bc.bootf = pkt.file;
	bc.dhcpip = IPaddr.newv6(pkt.udphdr[Udpraddr:]).text();
	bc.siaddr = pkt.siaddr.text();
	bc.lease = bc.getint(Olease);
	if(bc.lease == Infinite)
		bc.lease = 0;
	else if(debug > 1)
		bc.lease = 2*60;	# shorten time, for testing
	bc.dom = bc.gets(Odomainname);
	s := bc.gets(Ohostname);
	for(i:=0; i<len s; i++)
		if(s[i] == '.'){
			if(bc.dom == nil)
				bc.dom = s[i+1:];
			s = s[0:i];
			break;
		}
	bc.sys = s;
	bc.ipgw = bc.getip(Orouter);
	bc.bootip = bc.getip(Otftpserver);
	bc.serverid = bc.getip(Oserverid);
	return bc;
}

Lease.release(l: self ref Lease)
{
	# could send a Release message
	# should unconfigure
	if(l.pid){
		kill(l.pid, "grp");
		l.pid = 0;
	}
}

flush(c: chan of (ref Bootconf, string))
{
	alt{
	<-c =>	;
	* =>	;
	}
}

DhcpIO: adt {
	fd:	ref Sys->FD;
	pid:	int;
	dc:	chan of ref Dhcp;
	new:	fn(fd: ref Sys->FD): ref DhcpIO;
	rstart:	fn(io: self ref DhcpIO);
	rstop:	fn(io: self ref DhcpIO);
};

DhcpIO.new(fd: ref Sys->FD): ref DhcpIO
{
	return ref DhcpIO(fd, 0, chan of ref Dhcp);
}

DhcpIO.rstart(io: self ref DhcpIO)
{
	if(io.pid == 0){
		pids := chan of int;
		spawn dhcpreader(pids, io);
		io.pid = <-pids;
	}
}

DhcpIO.rstop(io: self ref DhcpIO)
{
	if(io.pid != 0){
		kill(io.pid, "");
		io.pid = 0;
	}
}

getopt(options: list of (int, array of byte), op: int, minlen: int): array of byte
{
	for(; options != nil; options = tl options){
		(opt, val) := hd options;
		if(opt == op && len val >= minlen)
			return val;
	}
	return nil;
}

exchange(srv: ref DhcpIO, xid: int, req: ref Dhcp, accept: int): ref Dhcp
{
	srv.rstart();
	nsec := 3;
	for(count := 0; count < 5; count++) {
		(tpid, tc) := timeoutstart(nsec*1000);
		dhcpsend(srv.fd, xid, req);
	   Wait:
		for(;;){
			alt {
			<-tc=>
				break Wait;
			rep := <-srv.dc=>
				if(debug)
					dumpdhcp(rep, "<-");
				if(rep.op == Bootpreply &&
				    rep.xid == req.xid &&
				    rep.ciaddr.eq(req.ciaddr) &&
				    eqbytes(rep.chaddr, req.chaddr)){
					if((accept & (1<<rep.dhcpop)) == 0){
						if(debug)
							sys->print("req: unexpected reply %s to %s\n", opname(rep.dhcpop), opname(req.dhcpop));
						continue;
					}
					kill(tpid, "");
					return rep;
				}
				if(debug)
					sys->print("req: mismatch\n");
			}
		}
		req.secs += nsec;
		nsec++;
	}
	return nil;
}

applycfg(net: string, ctlfd: ref Sys->FD, bc: ref Bootconf): string
{
	# write addresses to /net/...
	# local address, mask[or default], remote address [mtu]
	if(net == nil)
		net = "/net";
	if(bc.ip == nil)
		return  "invalid address";
	if(ctlfd != nil){
		if(sys->fprint(ctlfd, "add %s %s", bc.ip, bc.ipmask) < 0)	# TO DO: [raddr [mtu]]
			return sys->sprint("add interface: %r");
		# could use "mtu n" request to set/change mtu
	}
	# if primary:
	# 	add default route if gateway valid
	# 	put ndb entries ip=, ipmask=, ipgw=; sys= dom=; fs=; auth=; dns=; ntp=; other options from bc.options
	if(bc.ipgw != nil){
		fd := sys->open(net+"/iproute", Sys->OWRITE);
		if(fd != nil)
			sys->fprint(fd, "add 0 0 %s", bc.ipgw);
	}
	s := sys->sprint("ip=%s ipmask=%s", bc.ip, bc.ipmask);
	if(bc.ipgw != nil)
		s += sys->sprint(" ipgw=%s", bc.ipgw);
	s += "\n";
	if(bc.sys != nil)
		s += sys->sprint("	sys=%s\n", bc.sys);
	if(bc.dom != nil)
		s += sys->sprint("	dom=%s.%s\n", bc.sys, bc.dom);
	if((addr := bc.getip(OP9auth)) != nil)
		s += sys->sprint("	auth=%s\n", addr);	# TO DO: several addresses
	if((addr = bc.getip(OP9fs)) != nil)
		s += sys->sprint("	fs=%s\n", addr);
	if((addr = bc.getip(Odnsserver)) != nil)
		s += sys->sprint("	dns=%s\n", addr);
	fd := sys->open(net+"/ndb", Sys->OWRITE | Sys->OTRUNC);
	if(fd != nil){
		a := array of byte s;
		sys->write(fd, a, len a);
	}
	return nil;
}

removecfg(nil: string, ctlfd: ref Sys->FD, bc: ref Bootconf): string
{
	# remove localaddr, localmask[or default]
	if(ctlfd != nil){
		if(sys->fprint(ctlfd, "remove %s %s", bc.ip, bc.ipmask) < 0)
			return sys->sprint("remove address: %r");
	}
	bc.ip = nil;
	bc.ipgw = nil;
	bc.ipmask = nil;
	# remote address?
	# clear net+"/ndb"?
	return nil;
}

#
# the following is just for debugging
#

dumpdhcp(m: ref Dhcp, dir: string)
{
	s := "";
	sys->print("%s %s/%ud: ", dir, IPaddr.newv6(m.udphdr[Udpraddr:]).text(), get2(m.udphdr, Udprport));
	if(m.dhcpop != NotDHCP)
		s = " "+opname(m.dhcpop);
	sys->print("op %d%s htype %d hops %d xid %ud\n", m.op, s, m.htype, m.hops, m.xid);
	sys->print("\tsecs %d flags 0x%.4ux\n", m.secs, m.flags);
	sys->print("\tciaddr %s\n", m.ciaddr.text());
	sys->print("\tyiaddr %s\n", m.yiaddr.text());
	sys->print("\tsiaddr %s\n", m.siaddr.text());
	sys->print("\tgiaddr %s\n", m.giaddr.text());
	sys->print("\tchaddr ");
	for(x := 0; x < len m.chaddr; x++)
		sys->print("%2.2ux", int m.chaddr[x]);
	sys->print("\n");
	if(m.sname != nil)
		sys->print("\tsname %s\n", m.sname);
	if(m.file != nil)
		sys->print("\tfile %s\n", m.file);
	if(m.options != nil){
		sys->print("\t");
		printopts(m.options, opts);
		sys->print("\n");
	}
}

Optbytes, Optaddr, Optmask, Optint, Optstr, Optopts, Opthex: con iota;

Opt: adt
{
	code:	int;
	name:	string;
	otype:	int;
};

opts: array of Opt = array[] of {
	(Omask, "ipmask", Optmask),
	(Orouter, "ipgw", Optaddr),
	(Odnsserver, "dns", Optaddr),
	(Ohostname, "hostname", Optstr),
	(Odomainname, "domain", Optstr),
	(Ontpserver, "ntp", Optaddr),
	(Oipaddr, "requestedip", Optaddr),
	(Olease, "lease", Optint),
	(Oserverid, "serverid", Optaddr),
	(Otype, "dhcpop", Optint),
	(Ovendorclass, "vendorclass", Optstr),
	(Ovendorinfo, "vendorinfo", Optopts),
	(Onetbiosns, "wins", Optaddr),
	(Opop3server, "pop3", Optaddr),
	(Osmtpserver, "smtp", Optaddr),
	(Owwwserver, "www", Optaddr),
	(Oparams, "params", Optbytes),
	(Otftpserver, "tftp", Optaddr),
	(Oclientid, "clientid", Opthex),
};

p9opts: array of Opt = array[] of {
	(OP9fs, "fs", Optaddr),
	(OP9auth, "auth", Optaddr),
};

lookopt(optab: array of Opt, code: int): (int, string, int)
{
	for(i:=0; i<len optab; i++)
		if(opts[i].code == code)
			return opts[i];
	return (-1, nil, 0);
}

printopts(options: list of (int, array of byte), opts: array of Opt)
{
	for(; options != nil; options = tl options){
		(code, val) := hd options;
		sys->print("(%d %d", code, len val);
		(nil, name, otype) := lookopt(opts, code);
		if(name == nil){
			for(v := 0; v < len val; v++)
				sys->print(" %d", int val[v]);
		}else{
			sys->print(" %s", name);
			case otype {
			Optbytes =>
				for(v := 0; v < len val; v++)
					sys->print(" %d", int val[v]);
			Opthex =>
				for(v := 0; v < len val; v++)
					sys->print(" %#.2ux", int val[v]);
			Optaddr or Optmask =>
				while(len val >= 4){
					sys->print(" %s", v4text(val));
					val = val[4:];
				}
			Optstr =>
				sys->print(" \"%s\"", string val);
			Optint =>
				n := 0;
				for(v := 0; v < len val; v++)
					n = (n<<8) | int val[v];
				sys->print(" %d", n);
			Optopts =>
				printopts(parseopt(val, 0).t1, p9opts);
			}
		}
		sys->print(")");
	}
}
