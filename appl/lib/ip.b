implement IP;

#
# Copyright © 2003,2004 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "ip.m";

init()
{
	sys = load Sys Sys->PATH;
	v4prefix = array[] of {
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 16rFF, byte 16rFF,
	};

	v4bcast = IPaddr(array[] of {
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 16rFF, byte 16rFF,
		byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF,
	});

	v4allsys = IPaddr(array[] of {
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 16rFF, byte 16rFF,
		byte 16rE0, byte 0, byte 0, byte 16r01,
	});

	v4allrouter = IPaddr(array[] of {
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 16rFF, byte 16rFF,
		byte 16rE0, byte 0, byte 0, byte 16r02,
	});

	v4noaddr = IPaddr(array[] of {
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 16rFF, byte 16rFF,
		byte 0, byte 0, byte 0, byte 0,
	});

	selfv6 = IPaddr(array[] of {
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 1,
	});

	selfv4 = IPaddr(array[] of {
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 0, byte 0,
		byte 0, byte 0, byte 16rFF, byte 16rFF,
		byte 127, byte 0, byte 0, byte 1,
	});

	noaddr = IPaddr(array[] of {0 to IPaddrlen-1 => byte 0});
	allbits = IPaddr(array[] of {0 to IPaddrlen-1 => byte 16rFF});
}

IPaddr.newv6(a: array of byte): IPaddr
{
	b := array[IPaddrlen] of byte;
	b[0:] = a[0:IPaddrlen];
	return IPaddr(b);
}

IPaddr.newv4(a: array of byte): IPaddr
{
	b := array[IPaddrlen] of byte;
	b[0:] = v4prefix;
	b[IPv4off:] = a[0:IPv4addrlen];
	return IPaddr(b);
}

IPaddr.copy(ip: self IPaddr): IPaddr
{
	if(ip.a == nil)
		return noaddr.copy();
	a := array[IPaddrlen] of byte;
	a[0:] = ip.a;
	return IPaddr(a);
}

IPaddr.eq(ip: self IPaddr, v: IPaddr): int
{
	a := ip.a;
	if(a == nil)
		a = noaddr.a;
	b := v.a;
	if(b == nil)
		b = noaddr.a;
	for(i := 0; i < IPaddrlen; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

IPaddr.mask(a1: self IPaddr, a2: IPaddr): IPaddr
{
	c := array[IPaddrlen] of byte;
	for(i := 0; i < IPaddrlen; i++)
		c[i] = a1.a[i] & a2.a[i];
	return IPaddr(c);
}

IPaddr.maskn(a1: self IPaddr, a2: IPaddr): IPaddr
{
	c := array[IPaddrlen] of byte;
	for(i := 0; i < IPaddrlen; i++)
		c[i] = a1.a[i] & ~a2.a[i];
	return IPaddr(c);
}

IPaddr.isv4(ip: self IPaddr): int
{
	for(i := 0; i < IPv4off; i++)
		if(ip.a[i] != v4prefix[i])
			return 0;
	return 1;
}

IPaddr.ismulticast(ip: self IPaddr): int
{
	if(ip.isv4()){
		v := int ip.a[IPv4off];
		return v >= 16rE0 && v < 16rF0 || ip.eq(v4bcast);	# rfc1112
	}
	return ip.a[0] == byte 16rFF;
}

IPaddr.isvalid(ip: self IPaddr): int
{
	return !ip.eq(noaddr) && !ip.eq(v4noaddr);
}

IPaddr.v4(ip: self IPaddr): array of byte
{
	if(!ip.isv4() && !ip.eq(noaddr))
		return nil;
	a := array[4] of byte;
	for(i := 0; i < 4; i++)
		a[i] = ip.a[IPv4off+i];
	return a;
}

IPaddr.v6(ip: self IPaddr): array of byte
{
	a := array[IPaddrlen] of byte;
	a[0:] = ip.a;
	return a;
}

IPaddr.class(ip: self IPaddr): int
{
	if(!ip.isv4())
		return 6;
	return int ip.a[IPv4off]>>6;
}

IPaddr.classmask(ip: self IPaddr): IPaddr
{
	m := allbits.copy();
	if(!ip.isv4())
		return m;
	if((n := ip.class()) == 0)
		n = 1;
	for(i := IPaddrlen-4+n; i < IPaddrlen; i++)
		m.a[i] = byte 0;
	return m;
}

#
# rfc2373
#

IPaddr.parse(s: string): (int, IPaddr)
{
	a := noaddr.copy();
	col := 0;
	gap := 0;
	for(i:=0; i<IPaddrlen && s != ""; i+=2){
		c := 'x';
		v := 0;
		for(m := 0; m < len s && (c = s[m]) != '.' && c != ':'; m++){
			d := 0;
			if(c >= '0' && c <= '9')
				d = c-'0';
			else if(c >= 'a' && c <= 'f')
				d = c-'a'+10;
			else if(c >= 'A' && c <= 'F')
				d = c-'A'+10;
			else
				return (-1, a);
			v = (v<<4) | d;
		}
		if(c == '.'){
			if(parseipv4(a.a[i:], s) < 0)
				return (-1, noaddr.copy());
			i += IPv4addrlen;
			break;
		}
		if(v > 16rFFFF)
			return (-1, a);
		a.a[i] = byte (v>>8);
		a.a[i+1] = byte v;
		if(c == ':'){
			col = 1;
			if(++m < len s && s[m] == ':'){
				if(gap > 0)
					return (-1, a);
				gap = i+2;
				m++;
			}
		}
		s = s[m:];
	}
	if(i < IPaddrlen){	# mind the gap
		ns := i-gap;
		for(j := 1; j <= ns; j++){
			a.a[IPaddrlen-j] = a.a[i-j];
			a.a[i-j] = byte 0;
		}
	}
	if(!col)
		a.a[0:] = v4prefix;
	return (0, IPaddr(a));
}

IPaddr.parsemask(s: string): (int, IPaddr)
{
	return parsemask(s, 128);
}

IPaddr.parsecidr(s: string): (int, IPaddr, IPaddr)
{
	for(i := 0; i < len s && s[i] != '/'; i++)
		;
	(ok, a) := IPaddr.parse(s[0:i]);
	if(i < len s){
		(ok2, m) := IPaddr.parsemask(s[i:]);
		if(ok < 0 || ok2 < 0)
			return (-1, a, m);
		return (0, a, m);
	}
	return (ok, a, allbits.copy());
}

parseipv4(b: array of byte, s: string): int
{
	a := array[4] of {* => 0};
	o := 0;
	for(i := 0; i < 4 && o < len s; i++){
		for(m := o; m < len s && (c := s[m]) != '.'; m++)
			if(!(c >= '0' && c <= '9'))
				return -1;
		if(m == o)
			return -1;
		a[i] = int big s[o:m];
		b[i] = byte a[i];
		if(m < len s && s[m] == '.')
			m++;
		o = m;
	}
	case i {
	1 =>		# 32 bit
		b[0] = byte (a[0] >> 24);
		b[1] = byte (a[0] >> 16);
		b[2] = byte (a[0] >> 8);
		b[3] = byte a[0];
	2 =>
		if(a[0] < 256){	# 8/24
			b[0] = byte a[0];
			b[1] = byte (a[1]>>16);
			b[2] = byte (a[1]>>8);
		}else if(a[0] < 65536){	# 16/16
			b[0] = byte (a[0]>>8);
			b[1] = byte a[0];
			b[2] = byte (a[1]>>16);
		}else{	# 24/8
			b[0] = byte (a[0]>>16);
			b[1] = byte (a[0]>>8);
			b[2] = byte a[0];
		}
		b[3] = byte a[1];
	3 =>		# 8/8/16
		b[0] = byte a[0];
		b[1] = byte a[1];
		b[2] = byte (a[2]>>16);
		b[3] = byte a[2];
	}
	return 0;
}

parsemask(s: string, abits: int): (int, IPaddr)
{
	m := allbits.copy();
	if(s == nil)
		return (0, m);
	if(s[0] != '/'){
		(ok, a) := IPaddr.parse(s);
		if(ok < 0)
			return (0, m);
		if(a.isv4())
			a.a[0:] = m.a[0:IPv4off];
		return (0, a);
	}
	if(len s == 1)
		return (0, m);
	nbit := int s[1:];
	if(nbit < 0)
		return (-1, m);
	if(nbit > abits)
		return (0, m);
	nbit = abits-nbit;
	i := IPaddrlen;
	for(; nbit >= 8; nbit -= 8)
		m.a[--i] = byte 0;
	if(nbit > 0)
		m.a[i-1] &= byte (~0<<nbit);
	return (0, m);
}

IPaddr.text(a: self IPaddr): string
{
	b := a.a;
	if(b == nil)
		return "::";
	if(a.isv4())
		return sys->sprint("%d.%d.%d.%d", int b[IPv4off], int b[IPv4off+1], int b[IPv4off+2], int b[IPv4off+3]);
	cs := -1;
	nc := 0;
	for(i:=0; i<IPaddrlen; i+=2)
		if(int b[i] == 0 && int b[i+1] == 0){
			for(j:=i+2; j<IPaddrlen; j+=2)
				if(int b[j] != 0 || int b[j+1] != 0)
					break;
			if(j-i > nc){
				nc = j-i;
				cs = i;
			}
		}
	if(nc <= 2)
		cs = -1;
	s := "";
	for(i=0; i<IPaddrlen; ){
		if(i == cs){
			s += "::";
			i += nc;
		}else{
			if(s != "" && s[len s-1]!=':')
				s[len s] = ':';
			v := (int a.a[i] << 8) | int a.a[i+1];
			s += sys->sprint("%ux", v);
			i += 2;
		}
	}
	return s;
}

IPaddr.masktext(a: self IPaddr): string
{
	b := a.a;
	if(b == nil)
		return "/0";
	for(i:=0; i<IPaddrlen; i++)
		if(i == IPv4off)
			return sys->sprint("%d.%d.%d.%d", int b[IPv4off], int b[IPv4off+1], int b[IPv4off+2], int b[IPv4off+3]);
		else if(b[i] != byte 16rFF)
			break;
	for(j:=i+1; j<IPaddrlen; j++)
		if(b[j] != byte 0)
			return a.text();
	nbit := 8*i;
	if(i < IPaddrlen){
		v := int b[i];
		for(m := 16r80; m != 0; m >>= 1){
			if((v & m) == 0)
				break;
			v &= ~m;
			nbit++;
		}
		if(v != 0)
			return a.text();
	}
	return sys->sprint("/%d", nbit);
}

addressesof(ifcs: list of ref Ipifc, all: int): list of IPaddr
{
	ra: list of IPaddr;
	runi: list of IPaddr;
	for(; ifcs != nil; ifcs = tl ifcs){
		for(ifcas :=(hd ifcs).addrs; ifcs != nil; ifcs = tl ifcs){
			a := (hd ifcas).ip;
			if(all || !(a.eq(noaddr) || a.eq(v4noaddr))){	# ignore unspecified and loopback
				if(a.ismulticast() || a.eq(selfv4) || a.eq(selfv6))
					ra = a :: ra;
				else
					runi = a :: runi;
			}
		}
	}
	# unicast first, then others, both sets in order as found
	# for ipv6, might want to give priority to unicast other than link- and site-local
	al: list of IPaddr;
	for(; ra != nil; ra = tl ra)
		al = hd ra :: al;
	for(; runi != nil; runi = tl runi)
		al = hd runi :: al;
	return al;
}

interfaceof(l: list of ref Ipifc, ip: IPaddr): (ref Ipifc, ref Ifcaddr)
{
	for(; l != nil; l = tl l){
		ifc := hd l;
		for(addrs := ifc.addrs; addrs != nil; addrs = tl addrs){
			a := hd addrs;
			if(ip.mask(a.mask).eq(a.net))
				return (ifc, a);
		}
	}
	return (nil, nil);
}

ownerof(l: list of ref Ipifc, ip: IPaddr): (ref Ipifc, ref Ifcaddr)
{
	for(; l != nil; l = tl l){
		ifc := hd l;
		for(addrs := ifc.addrs; addrs != nil; addrs = tl addrs){
			a := hd addrs;
			if(ip.eq(a.ip))
				return (ifc, a);
		}
	}
	return (nil, nil);
}

readipifc(net: string, index: int): (list of ref Ipifc, string)
{
	if(net == nil)
		net = "/net";
	if(index < 0){
		ifcs: list of ref Ipifc;
		dirfd := sys->open(net+"/ipifc", Sys->OREAD);
		if(dirfd == nil)
			return (nil, sys->sprint("%r"));
		err: string;
		for(;;){
			(nd, dirs) := sys->dirread(dirfd);
			if(nd <= 0){
				if(nd < 0)
					err = sys->sprint("%r");
				break;
			}
			for(i:=0; i<nd; i++)
				if((dn := dirs[i].name) != nil && dn[0]>='0' && dn[0]<='9'){
					index = int dn;
					ifc := readstatus(net+"/ipifc/"+dn+"/status", index);
					if(ifc != nil)
						ifcs = ifc :: ifcs;
				}
		}
		l := ifcs;
		for(ifcs = nil; l != nil; l = tl l)
			ifcs = hd l :: ifcs;
		return (ifcs, err);
	}
	ifc := readstatus(net+"/ipifc/"+string index+"/status", index);
	if(ifc == nil)
		return (nil, sys->sprint("%r"));
	return (ifc :: nil, nil);
}

#
# return data structure containing values read from status file:
#
# device /net/ether0 maxtu 1514 sendra 0 recvra 0 mflag 0 oflag 0 maxraint 600000 minraint 200000 linkmtu 0 reachtime 0 rxmitra 0 ttl 255 routerlt 1800000 pktin 47609 pktout 42322 errin 0 errout 0
#	144.32.112.83 /119 144.32.112.0 4294967295   4294967295
#		...
#

readstatus(file: string, index: int): ref Ipifc
{
	fd := sys->open(file, Sys->OREAD);
	if(fd == nil)
		return nil;
	contents := slurp(fd);
	fd = nil;
	(nline, lines) := sys->tokenize(contents, "\n");
	if(nline <= 0){
		sys->werrstr("unexpected ipifc status file format");
		return nil;
	}
	(nil, details) := sys->tokenize(hd lines, " \t\n");
	lines = tl lines;
	ifc := ref Ipifc;
	ifc.index = index;
	ifc.dev = valof(details, "device");
	ifc.mtu = int valof(details, "maxtu");
	ifc.pktin = big valof(details, "pktin");
	ifc.pktout = big valof(details, "pktout");
	ifc.errin = big valof(details, "errin");
	ifc.errout = big valof(details, "errout");
	ifc.sendra = int valof(details, "sendra");
	ifc.recvra = int valof(details, "recvra");
	ifc.rp.mflag = int valof(details, "mflag");
	ifc.rp.oflag = int valof(details, "oflag");
	ifc.rp.maxraint = int valof(details, "maxraint");
	ifc.rp.minraint = int valof(details, "minraint");
	ifc.rp.linkmtu = int valof(details, "linkmtu");
	ifc.rp.reachtime = int valof(details, "reachtime");
	ifc.rp.rxmitra = int valof(details, "rxmitra");
	ifc.rp.ttl = int valof(details, "ttl");
	ifc.rp.routerlt = int valof(details, "routerlt");
	addrs: list of ref Ifcaddr;
	for(; lines != nil; lines = tl lines){
		(nf, fields) := sys->tokenize(hd lines, " \t\n");
		if(nf >= 3){
			addr := ref Ifcaddr;
			(nil, addr.ip) = IPaddr.parse(hd fields); fields = tl fields;
			(nil, addr.mask) = IPaddr.parsemask(hd fields); fields = tl fields;
			(nil, addr.net) = IPaddr.parse(hd fields); fields = tl fields;
			if(nf >= 5){
				addr.preflt = big hd fields; fields = tl fields;
				addr.validlt = big hd fields; fields = tl fields;
			}else{
				addr.preflt = big 0;
				addr.validlt = big 0;
			}
			addrs = addr :: addrs;
		}
	}
	for(; addrs != nil; addrs = tl addrs)
		ifc.addrs = hd addrs :: ifc.addrs;
	return ifc;
}

slurp(fd: ref Sys->FD): string
{
	buf := array[2048] of byte;
	s := "";
	while((n := sys->read(fd, buf, len buf)) > 0)
		s += string buf[0:n];
	return s;
}

valof(l: list of string, attr: string): string
{
	while(l != nil){
		label := hd l;
		l = tl l;
		if(label == attr){
			if(l == nil)
				return nil;
			return hd l;
		}
		if(l != nil)
			l = tl l;
	}
	return nil;
}

Udphdr.new(): ref Udphdr
{
	return ref Udphdr(noaddr, noaddr, noaddr, 0, 0);
}

Udphdr.unpack(a: array of byte, n: int): ref Udphdr
{
	case n {
	Udp4hdrlen =>
		u := ref Udphdr;
		u.raddr = IPaddr.newv4(a[0:]);
		u.laddr = IPaddr.newv4(a[IPv4addrlen:]);
		u.rport = get2(a, 2*IPv4addrlen);
		u.lport = get2(a, 2*IPv4addrlen+2);
		u.ifcaddr = u.laddr.copy();
		return u;
	OUdphdrlen =>
		u := ref Udphdr;
		u.raddr = IPaddr.newv6(a[0:]);
		u.laddr = IPaddr.newv6(a[IPaddrlen:]);
		u.rport = get2(a, 2*IPaddrlen);
		u.lport = get2(a, 2*IPaddrlen+2);
		u.ifcaddr = u.laddr.copy();
		return u;
	Udphdrlen =>
		u := ref Udphdr;
		u.raddr = IPaddr.newv6(a[0:]);
		u.laddr = IPaddr.newv6(a[IPaddrlen:]);
		u.ifcaddr = IPaddr.newv6(a[2*IPaddrlen:]);
		u.rport = get2(a, 3*IPaddrlen);
		u.lport = get2(a, 3*IPaddrlen+2);
		return u;
	* =>
		raise "Udphdr.unpack: bad length";
	}
}

Udphdr.pack(u: self ref Udphdr, a: array of byte, n: int)
{
	case n {
	Udp4hdrlen =>
		a[0:] = u.raddr.v4();
		a[IPv4addrlen:] = u.laddr.v4();
		put2(a, 2*IPv4addrlen, u.rport);
		put2(a, 2*IPv4addrlen+2, u.lport);
	OUdphdrlen =>
		a[0:] = u.raddr.v6();
		a[IPaddrlen:] = u.laddr.v6();
		put2(a, 2*IPaddrlen, u.rport);
		put2(a, 2*IPaddrlen+2, u.lport);
	Udphdrlen =>
		a[0:] = u.raddr.v6();
		a[IPaddrlen:] = u.laddr.v6();
		a[2*IPaddrlen:] = u.ifcaddr.v6();
		put2(a, 3*IPaddrlen, u.rport);
		put2(a, 3*IPaddrlen+2, u.lport);
	* =>
		raise "Udphdr.pack: bad length";
	}
}

get2(a: array of byte, o: int): int
{
	return (int a[o] << 8) | int a[o+1];
}

put2(a: array of byte, o: int, val: int): int
{
	a[o] = byte (val>>8);
	a[o+1] = byte val;
	return o+2;
}

get4(a: array of byte, o: int): int
{
	return (((((int a[o] << 8)| int a[o+1]) << 8) | int a[o+2]) << 8) | int a[o+3];
}
	
put4(a: array of byte, o: int, val: int): int
{
	a[o] = byte (val>>24);
	a[o+1] = byte (val>>16);
	a[o+2] = byte (val>>8);
	a[o+3] = byte val;
	return o+4;
}
