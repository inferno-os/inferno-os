Dhcpclient: module
{
	PATH: con "/dis/lib/dhcpclient.dis";

	Bootconf: adt {
		ip:	string;
		ipgw:	string;
		ipmask:	string;
		bootf:	string;
		bootip:	string;
		dhcpip:	string;
		siaddr:	string;
		serverid:	string;
		sys:	string;
		dom:	string;
		lease:	int;
		options:	array of array of byte;
		vendor:	array of array of byte;

		new:	fn(): ref Bootconf;
		get:	fn(c: self ref Bootconf, n: int): array of byte;
		getint:	fn(c: self ref Bootconf, n: int): int;
		getip:	fn(c: self ref Bootconf, n: int): string;
		getips:	fn(c: self ref Bootconf, n: int): list of string;
		gets:	fn(c: self ref Bootconf, n: int): string;
		put:	fn(c: self ref Bootconf, n: int, a: array of byte);
		putint:	fn(c: self ref Bootconf, n: int, v: int);
		putips:	fn(c: self ref Bootconf, n: int, ips: list of string);
		puts:	fn(c: self ref Bootconf, n: int, s: string);
	};

	Lease: adt {
		pid:	int;
		configs:	chan of (ref Bootconf, string);

		release:	fn(l: self ref Lease);
	};

	init:	fn();
	tracing:	fn(debug: int);
	bootp:	fn(net: string, ctlifc: ref Sys->FD, device: string, init: ref Bootconf): (ref Bootconf, string);
	dhcp:	fn(net: string, ctlifc: ref Sys->FD, device: string, init: ref Bootconf, options: array of int): (ref Bootconf, ref Lease, string);

	applycfg:	fn(net: string, ctlifc: ref Sys->FD, conf: ref Bootconf): string;
	removecfg:	fn(net: string, ctlifc: ref Sys->FD, conf: ref Bootconf): string;

	# bootp options used here
	Opad: con 0;
	Oend: con 255;
	Omask: con 1;
	Orouter: con 3;
	Odnsserver: con 6;
	Ocookieserver: con 8;
	Ohostname: con 12;
	Odomainname: con 15;
	Ontpserver: con 42;
	Ovendorinfo: con 43;
	Onetbiosns: con 44;
	Osmtpserver: con 69;
	Opop3server: con 70;
	Owwwserver: con 72;

	# dhcp options
	Oipaddr: con 50;
	Olease: con 51;
	Ooverload: con 52;
	Otype: con 53;
	Oserverid: con 54;
	Oparams: con 55;
	Omessage: con 56;
	Omaxmsg: con 57;
	Orenewaltime: con 58;
	Orebindingtime: con 59;
	Ovendorclass: con 60;
	Oclientid: con 61;
	Otftpserver: con 66;
	Obootfile: con 67;

	Ovendor:	con (1<<8);
	OP9fs: con Ovendor|128;	# plan 9 file server
	OP9auth:	con Ovendor|129;	# plan 9 auth server

	Infinite:	con ~0;	# lease
};
