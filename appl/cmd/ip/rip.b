implement Rip;

# basic RIP implementation
#	understands v2, sends v1

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "daytime.m";
	daytime: Daytime;

include "ip.m";
	ip: IP;
	IPaddr, Ifcaddr, Udphdr: import ip;

include "attrdb.m";
	attrdb: Attrdb;

include "arg.m";

Rip: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

# rip header:
#	op[1] version[1] pad[2]

Oop: con 0;	# op: byte
Oversion: con 1;	# version: byte
Opad: con 2;	# 2 byte pad
Riphdrlen: con	Opad+2;	# op[1] version[1] mbz[2]

# rip route entry:
#	type[2] tag[2] addr[4] mask[4] nexthop[4] metric[4]

Otype: con 0;	# type[2]
Otag: con Otype+2;	# tag[2] v2 or mbz v1
Oaddr: con Otag+2;	# addr[4]
Omask: con Oaddr+4;	# mask[4] v2 or mbz v1
Onexthop: con Omask+4;
Ometric: con Onexthop+4;	# metric[4]
Ipdestlen: con Ometric+4;

Maxripmsg: con 512;

# operations
OpRequest: con 1;		# want route
OpReply: con 2;		# all or part of route table

HopLimit: con 16;		# defined by protocol as `infinity'
RoutesInPkt: con 25; 	# limit defined by protocol
RIPport: con 520;

Expired: con 180;
Discard: con 240;

OutputRate: con 60;	# seconds between routing table transmissions

NetworkCost: con 1;	# assume the simple case

Gateway: adt {
	dest:	IPaddr;
	mask:	IPaddr;
	gateway:	IPaddr;
	metric:	int;
	valid:	int;
	changed:	int;
	local:	int;
	time:	int;

	contains:	fn(g: self ref Gateway, a: IPaddr): int;
};

netfd:	ref Sys->FD;
routefd:	ref Sys->FD;
AF_INET:	con 2;

routes: array of ref Gateway;
Routeinc: con 50;
defroute: ref Gateway;
debug := 0;
nochange := 0;
quiet := 1;
myversion := 1;	# default protocol version
logfile := "iproute";
netdir := "/net";
now: int;
nets: list of ref Ifcaddr;
addrs: list of IPaddr;

syslog(nil: int, nil: string, s: string)
{
	sys->print("rip: %s\n", s);
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;
	ip = load IP IP->PATH;
	ip->init();

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("ip/rip [-d] [-r]");
	while((o := arg->opt()) != 0)
		case o {
		'd' =>	debug++;
		'b' =>	quiet = 0;
		'2' =>	myversion = 2;
		'n' =>	nochange = 1;
		'x' =>	netdir = arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(args != nil)
		quiet = 0;
	for(; args != nil; args = tl args){
		(ok, a) := IPaddr.parse(hd args);
		if(ok < 0)
			fatal(sys->sprint("invalid address: %s", hd args));
		addrs = a :: addrs;
	}
	arg = nil;

	sys->pctl(Sys->NEWPGRP|Sys->FORKFD|Sys->FORKNS, nil);

	whereami();
	addlocal();

	routefd = sys->open(sys->sprint("%s/iproute", netdir), Sys->ORDWR);
	if(routefd == nil)
		fatal(sys->sprint("can't open %s/iproute: %r", netdir));
	readroutes();

	syslog(0, logfile, "started");

	netfd = riplisten();

	# broadcast request for all routes

	if(!quiet){
		sendall(OpRequest, 0);
		spawn sender();
	}

	# read routing requests

	buf := array[8192] of byte;
	while((nb := sys->read(netfd, buf, len buf)) > 0){
		nb -= Riphdrlen + IP->Udphdrlen;
		if(nb < 0)
			continue;
		uh := Udphdr.unpack(buf, IP->Udphdrlen);
		hdr := buf[IP->Udphdrlen:];
		version := int hdr[Oversion];
		if(version < 1)
			continue;
		bp := buf[IP->Udphdrlen + Riphdrlen:];
		case int hdr[Oop] {
		OpRequest =>
			# TO DO: transmit in response to request?  only if something interesting to say...
			;

		OpReply =>
			# wrong source port?
			if(uh.rport != RIPport)
				continue;
			# my own broadcast?
			if(ismyaddr(uh.raddr))
				continue;
			now = daytime->now();
			if(debug > 1)
				sys->fprint(sys->fildes(2), "from %s:\n", uh.raddr.text());
			for(; (nb -= Ipdestlen) >= 0; bp = bp[Ipdestlen:])
				unpackroute(bp, version, uh.raddr);
		* =>
			if(debug)
				sys->print("rip: unexpected op: %d\n", int hdr[Oop]);
		}
	}
}

whereami()
{
	for(ifcs := ip->readipifc(netdir, -1).t0; ifcs != nil; ifcs = tl ifcs)
		for(al := (hd ifcs).addrs; al != nil; al = tl al){
			ifa := hd al;
			if(!ifa.ip.isv4())
				continue;
			# how to tell broadcast? must be told? actually, it's in /net/iproute
			nets = ifa :: nets;
		}
}

ismyaddr(a: IPaddr): int
{
	for(l := nets; l != nil; l = tl l)
		if((hd l).ip.eq(a))
			return 1;
	return 0;
}

addlocal()
{
	for(l := nets; l != nil; l = tl l){
		ifc := hd l;
		g := lookup(ifc.net);
		g.valid = 1;
		g.local = 1;
		g.gateway = ifc.ip;
		g.mask = ifc.mask;
		g.metric = NetworkCost;
		g.time = 0;
		g.changed = 1;
		if(debug)
			syslog(0, logfile, sys->sprint("Existing: %s & %s -> %s", g.dest.text(), g.mask.masktext(), g.gateway.text()));
	}
}

#
# record any existing routes
#
readroutes()
{
	now = daytime->now();
	b := bufio->fopen(routefd, Sys->OREAD);
	while((l := b.gets('\n')) != nil){
		(nf, flds) := sys->tokenize(l, " \t");
		if(nf >= 5){
			flags := hd tl tl tl flds;
			if(flags == nil || flags[0] != '4' || contains(flags, "ibum"))
				continue;
			g := lookup(parseip(hd flds));
			g.mask = parsemask(hd tl flds);
			g.gateway = parseip(hd tl tl flds);
			g.metric = HopLimit;
			g.time = now;
			g.changed = 1;
			if(debug)
				syslog(0, logfile, sys->sprint("Existing: %s & %s -> %s", g.dest.text(), g.mask.masktext(), g.gateway.text()));
			if(iszero(g.dest) && iszero(g.mask)){
				defroute = g;
				g.local = 1;
			}else if(defroute != nil && g.dest.eq(defroute.gateway))
				continue;
			else
				g.local = !ismyaddr(g.gateway);
		}
	}
}

unpackroute(b: array of byte, version: int, gwa: IPaddr)
{
	# check that it's an IP route, valid metric, MBZ fields zero

	if(b[0] != byte 0 || b[1] != byte AF_INET){
		if(debug > 1)
			sys->fprint(sys->fildes(2), "\t-- unknown address type %x,%x\n", int b[0], int b[1]);
		return;
	}
	dest := IPaddr.newv4(b[Oaddr:]);
	mask: IPaddr;
	if(version == 1){
		# check MBZ fields
		if(ip->get2(b, 2) | ip->get4(b, Omask) | ip->get4(b, Onexthop)){
			if(debug > 1)
				sys->fprint(sys->fildes(2), "\t-- non-zero MBZ\n");
			return;
		}
		mask = maskgen(dest);
	}else if(version == 2){
		if(ip->get4(b, Omask))
			mask = IPaddr.newv4(b[Omask:]);
		else
			mask = maskgen(dest);
		if(ip->get4(b, Onexthop))
			gwa = IPaddr.newv4(b[Onexthop:]);
	}
	metric := ip->get4(b, Ometric);
	if(debug > 1)
		sys->fprint(sys->fildes(2), "\t%s %d\n", dest.text(), metric);
	if(metric <= 0 || metric > HopLimit)
		return;

	# 1058/3.4.2: response processing
	# ignore route if IP address is:
	#	class D or E
	#	net 0 (except perhaps 0.0.0.0)
	#	net 127
	#	broadcast address (all 1s host part)
	# we allow host routes

	if(dest.ismulticast() || dest.a[0] == byte 0 || dest.a[0] == byte 16r7F){
		if(debug > 1)
			sys->fprint(sys->fildes(2), "\t%s %d invalid addr\n", dest.text(), metric);
		return;
	}
	if(isbroadcast(dest, mask)){
		if(debug > 1)
			sys->fprint(sys->fildes(2), "\t%s & %s -> broadcast\n", dest.text(), mask.masktext());
		return;
	}

	# update the metric min(metric+NetworkCost, HopLimit)

	metric += NetworkCost;
	if(metric > HopLimit)
		metric = HopLimit;

	updateroute(dest, mask, gwa, metric);
}

updateroute(dest, mask, gwa: IPaddr, metric: int)
{
	# RFC1058 rules page 27-28, with optional replacement of expiring routes
	r := lookup(dest);
	if(r.valid){
		if(r.local)
			return;	# local, don't touch
		if(r.gateway.eq(gwa)){
			if(metric != HopLimit){
				r.metric = metric;
				r.time = now;
			}else{
				# metric == HopLimit
				if(r.metric != HopLimit){
					r.metric = metric;
					r.changed = 1;
					r.time = now - (Discard-120);
					delroute(r);	# don't use it for routing
					# route remains valid but advertised with metric HopLimit
				} else if(now >= r.time+Discard){
					delroute(r);	# finally dead
					r.valid = 0;
					r.changed = 1;
				}
			}
		}else if(metric < r.metric ||
			  metric != HopLimit && metric == r.metric && now > r.time+Expired/2){
			delroute(r);
			r.metric = metric;
			r.gateway = gwa;
			r.time = now;
			addroute(r);
		}
	} else if(metric < HopLimit){	# new entry

		# 1058/3.4.2: don't add route-to-host if host is on net/subnet
		# for which we have at least as good a route

		if(!mask.eq(ip->allbits) ||
		   ((pr := findroute(dest)) == nil || metric <= pr.metric)){
			r.valid = 1;
			r.changed = 1;
			r.time = now;
			r.metric = metric;
			r.dest = dest;
			r.mask = mask;
			r.gateway = gwa;
			addroute(r);
		}
	}
}

sender()
{
	for(;;){
		sys->sleep(OutputRate*1000);	# could add some random fizz
		sendall(OpReply, 1);
	}
}

onlist(a: IPaddr, l: list of IPaddr): int
{
	for(; l != nil; l = tl l)
		if(a.eq(hd l))
			return 1;
	return 0;
}

sendall(op: int, changes: int)
{
	for(l := nets; l != nil; l = tl l){
		if(addrs != nil && !onlist((hd l).net, addrs))
			continue;
		a := (hd l).net.copy();
		b := (ip->allbits).maskn((hd l).mask);
		for(i := 0; i < len a.a; i++)
			a.a[i] |= b.a[i];
		sendroutes(hd l, a, op, changes);
	}
	for(i := 0; i < len routes; i++)
		if((r := routes[i]) != nil)
			r.changed = 0;
}

zeroentry := array[Ipdestlen] of {* => byte 0};

sendroutes(ifc: ref Ifcaddr, dst: IPaddr, op: int, changes: int)
{
	if(debug > 1)
		sys->print("rip: send %s\n", dst.text());
	buf := array[Maxripmsg+IP->Udphdrlen] of byte;
	hdr := Udphdr.new();
	hdr.lport = hdr.rport = RIPport;
	hdr.raddr = dst;	# needn't copy
	hdr.pack(buf, IP->Udphdrlen);
	o := IP->Udphdrlen;
	buf[o] = byte op;
	buf[o+1] = byte myversion;
	buf[o+2] = byte 0;
	buf[o+3] = byte 0;
	o += Riphdrlen;
	rips := buf[IP->Udphdrlen+Riphdrlen:];
	if(op == OpRequest){
		buf[o:] = zeroentry;
		ip->put4(buf, o+Ometric, HopLimit);
		o += Ipdestlen;
	} else {
		# send routes
		for(i:=0; i<len routes; i++){
			r := routes[i];
			if(r == nil || !r.valid || changes && !r.changed)
				continue;
			if(r == defroute)
				continue;
			if(r.dest.eq(ifc.net) || isonnet(r.dest, ifc))
				continue;
			netmask := r.dest.classmask();
			subnet := !r.mask.eq(netmask);
			if(myversion < 2 && !r.mask.eq(ip->allbits)){
				# if not a host route, don't let a subnet route leave its net
				if(subnet && !netmask.eq(ifc.ip.classmask()))
					continue;
			}
			if(o+Ipdestlen > IP->Udphdrlen+Maxripmsg){
				if(sys->write(netfd, buf, o) < 0)
					sys->fprint(sys->fildes(2), "RIP write failed: %r\n");
				o = IP->Udphdrlen + Riphdrlen;
			}
			buf[o:] = zeroentry;
			ip->put2(buf, o+Otype, AF_INET);
			buf[o+Oaddr:] = r.dest.v4();
			ip->put4(buf, o+Ometric, r.metric);
			if(myversion == 2 && subnet)
				buf[o+Omask:] = r.mask.v4();
			o += Ipdestlen;
		}
	}
	if(o > IP->Udphdrlen+Riphdrlen && sys->write(netfd, buf, o) < 0)
		sys->fprint(sys->fildes(2), "rip: network write to %s failed: %r\n", dst.text());
}

lookup(addr: IPaddr): ref Gateway
{
	avail := -1;
	for(i:=0; i<len routes; i++){
		g := routes[i];
		if(g == nil || !g.valid){
			if(avail < 0)
				avail = i;
			continue;
		}
		if(g.dest.eq(addr))
			return g;
	}
	if(avail < 0){
		avail = len routes;
		a := array[len routes+Routeinc] of ref Gateway;
		a[0:] = routes;
		routes = a;
	}
	if((g := routes[avail]) == nil){
		g = ref Gateway;
		routes[avail] = g;
		g.valid = 0;
	}
	g.dest = addr;
	return g;
}

findroute(a: IPaddr): ref Gateway
{
	pr: ref Gateway;
	for(i:=0; i<len routes; i++){
		r := routes[i];
		if(r == nil || !r.valid)
			continue;
		if(r.contains(a) && (pr == nil || !maskle(r.mask, pr.mask)))
			pr = r;	# more specific mask
	}
	return pr;
}

maskgen(addr: IPaddr): IPaddr
{
	net: ref Ifcaddr;
	for(l := nets; l != nil; l = tl l){
		ifc := hd l;
		if(isonnet(addr, ifc) &&
		   (net == nil || maskle(ifc.mask, net.mask)))	# less specific mask?
			net = ifc;
	}
	if(net != nil)
		return net.mask;
	return addr.classmask();
}

isonnet(a: IPaddr, n: ref Ifcaddr): int
{
	return a.mask(n.mask).eq(n.net);
}

isbroadcast(a: IPaddr, mask: IPaddr): int
{
	h := a.maskn(mask);	# host part
	hm := (ip->allbits).maskn(mask);	# host part of mask
	return h.eq(hm);
}

iszero(a: IPaddr): int
{
	return a.eq(ip->v4noaddr) || a.eq(ip->noaddr);
}

maskle(a, b: IPaddr): int
{
	return a.mask(b).eq(a);
}

#
# add ipdest mask gateway
# add 0.0.0.0 0.0.0.0 gateway	(default)
# delete ipdest mask
#
addroute(g: ref Gateway)
{
	if(iszero(g.mask) && iszero(g.dest))
		g.valid = 0;	# don't change default route
	else if(defroute != nil && defroute.gateway.eq(g.gateway)){
		if(debug)
			syslog(0, logfile, sys->sprint("default %s %s", g.dest.text(), g.mask.text()));	# don't need a new entry
		g.valid = 1;
		g.changed = 1;
	} else {
		if(debug)
			syslog(0, logfile, sys->sprint("add %s %s %s", g.dest.text(), g.mask.text(), g.gateway.text()));
		if(nochange || sys->fprint(routefd, "add %s %s %s", g.dest.text(), g.mask.text(), g.gateway.text()) > 0){
			g.valid = 1;
			g.changed = 1;
		}
	}
}

delroute(g: ref Gateway)
{
	if(debug)
		syslog(0, logfile, sys->sprint("delete %s %s", g.dest.text(), g.mask.text()));
	if(!nochange)
		sys->fprint(routefd, "delete %s %s", g.dest.text(), g.mask.text());
}

parseip(s: string): IPaddr
{
	(ok, a) := IPaddr.parse(s);
	if(ok < 0)
		raise "bad route";
	return a;
}

parsemask(s: string): IPaddr
{
	(ok, a) := IPaddr.parsemask(s);
	if(ok < 0)
		raise "bad route";
	return a;
}

contains(s: string, t: string): int
{
	for(i := 0; i < len s; i++)
		for(j := 0; j < len t; j++)
			if(s[i] == t[j])
				return 1;
	return 0;
}

Gateway.contains(g: self ref Gateway, a: IPaddr): int
{
	return g.dest.eq(a.mask(g.mask));
}

riplisten(): ref Sys->FD
{
	addr := sys->sprint("%s/udp!*!rip", netdir);
	(ok, c) := sys->announce(addr);
	if(ok < 0)
		fatal(sys->sprint("can't announce %s: %r", addr));
	if(sys->fprint(c.cfd, "headers") < 0)
		fatal(sys->sprint("can't set udp headers: %r"));
	fd := sys->open(c.dir+"/data", Sys->ORDWR);
	if(fd == nil)
		fatal(sys->sprint("can't open %s: %r", c.dir+"/data"));
	return fd;
}

fatal(s: string)
{
	syslog(0, logfile, s);
	raise "fail:error";
}
