IP: module
{
	PATH:	con "/dis/lib/ip.dis";

	IPaddrlen:	con 16;
	IPv4addrlen:	con 4;
	IPv4off: con 12;

	IPaddr: adt {
		a:	array of byte;

		newv6:	fn(nil: array of byte): IPaddr;
		newv4:	fn(nil: array of byte): IPaddr;
		copy:	fn(nil: self IPaddr): IPaddr;
		eq:	fn(nil: self IPaddr, v: IPaddr): int;
		mask:	fn(nil: self IPaddr, m: IPaddr): IPaddr;
		maskn:	fn(nil: self IPaddr, m: IPaddr): IPaddr;
		isv4:	fn(nil: self IPaddr): int;
		ismulticast:	fn(nil: self IPaddr): int;
		isvalid:	fn(nil: self IPaddr): int;

		v4:	fn(nil: self IPaddr): array of byte;
		v6:	fn(nil: self IPaddr): array of byte;
		class:	fn(nil: self IPaddr): int;
		classmask:	fn(nil: self IPaddr): IPaddr;

		parse:	fn(s: string): (int, IPaddr);
		parsemask:	fn(s: string): (int, IPaddr);
		parsecidr:	fn(s: string): (int, IPaddr, IPaddr);

		text:	fn(nil: self IPaddr): string;
		masktext:	fn(nil: self IPaddr): string;
	};

	v4bcast, v4allsys, v4allrouter, v4noaddr, noaddr, allbits, selfv6, selfv4: IPaddr;
	v4prefix: array of byte;

	Ifcaddr: adt {
		ip:	IPaddr;
		mask:	IPaddr;
		net:	IPaddr;
		preflt:	big;
		validlt:	big;
	};

	Ipifc: adt {
		index:	int;	# /net/ipifc/N
		dev:	string;	# bound device
		addrs:	list of ref Ifcaddr;
		sendra:	int;	# !=0, send router adverts
		recvra:	int;	# !=0, receive router adverts
		mtu:	int;
		pktin:	big;	# packets in
		pktout:	big;	# packets out
		errin:	big;	# input errors
		errout:	big;	# output errors
		rp:	IPv6rp;	# IPv6 route advert params
	};

	IPv6rp: adt {
		mflag:	int;
		oflag:	int;
		maxraint:	int;	# max route advert interval
		minraint:	int;	# min route advert interval
		linkmtu:	int;
		reachtime:	int;
		rxmitra:	int;
		ttl:	int;
		routerlt:	int;
	};

	Udp4hdrlen:	con 2*IPv4addrlen+2*2;
	OUdphdrlen:	con 2*IPaddrlen+2*2;

	Udphdrlen:	con 52;
	Udpraddr:	con 0;
	Udpladdr: con Udpraddr + IPaddrlen;
	Udpifcaddr: con Udpladdr + IPaddrlen;
	Udprport: con Udpifcaddr + IPaddrlen;
	Udplport: con Udprport + 2;

	Udphdr: adt {
		raddr:	IPaddr;
		laddr:	IPaddr;
		ifcaddr:	IPaddr;
		rport:	int;
		lport:	int;

		new:		fn(): ref Udphdr;
		unpack:	fn(a: array of byte, n: int): ref Udphdr;
		pack:	fn(h: self ref Udphdr, a: array of byte, n: int);
	};

	init:	fn();
	readipifc:	fn(net: string, index: int): (list of ref Ipifc, string);
	addressesof:	fn(l: list of ref Ipifc, all: int): list of IPaddr;
	interfaceof:	fn(l: list of ref Ipifc, ip: IPaddr): (ref Ipifc, ref Ifcaddr);
	ownerof:	fn(l: list of ref Ipifc, ip: IPaddr): (ref Ipifc, ref Ifcaddr);

	get2:	fn(a: array of byte, o: int): int;
	put2:	fn(a: array of byte, o: int, v: int): int;
	get4:	fn(a: array of byte, o: int): int;
	put4:	fn(a: array of byte, o: int, v: int): int;
};
