Dial: module
{
	PATH: con "/dis/lib/dial.dis";

	Connection: adt
	{
		dfd:	ref Sys->FD;
		cfd:	ref Sys->FD;
		dir:	string;
	};

	Conninfo: adt
	{
		dir:	string;
		root:	string;
		spec:	string;
		lsys:	string;
		lserv:	string;
		rsys:	string;
		rserv:	string;
		laddr:	string;
		raddr:	string;
	};

	announce:	fn(addr: string): ref Connection;
	dial:	fn(addr, local: string): ref Connection;
	listen:	fn(c: ref Connection): ref Connection;
	accept:	fn(c: ref Connection): ref Sys->FD;
	reject:	fn(c: ref Connection, why: string): int;
#	parse:	fn(addr: string): (string, string, string);

	netmkaddr:	fn(addr, net, svc: string): string;
	netinfo:	fn(c: ref Connection): ref Conninfo;
};
