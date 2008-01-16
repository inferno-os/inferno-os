Factotum: module
{
	PATH:	con "/dis/lib/factotum.dis";

	# client interface to Plan 9 or Inferno factotum

	Authinfo: adt {
		cuid:	string;	# caller id
		suid:	string;	# server id
		cap:	string;	# capability (only valid on server side)
		secret:	array of byte;

		unpack:	fn(a: array of byte): (int, ref Authinfo);
		read:	fn(fd: ref Sys->FD): ref Authinfo;
	};

	mount:	fn(fd: ref Sys->FD, mnt: string, flags: int, aname: string, keyspec: string): (int, ref Authinfo);

	# factotum interaction
	AuthRpcMax: con 4096;

	init:	fn();
	rpc:	fn(fd: ref Sys->FD, verb: string, a: array of byte): (string, array of byte);
	proxy:	fn(afd: ref Sys->FD, facfd: ref Sys->FD, arg: string): ref Authinfo;
	genproxy: fn(
		readc: chan of (array of byte, chan of (int, string)),
		writec: chan of (array of byte, chan of (int, string)),
		donec: chan of (ref Authinfo, string),
		afd: ref Sys->FD,
		params: string);

	getuserpasswd:	fn(keyspec: string): (string, string);

	dump:	fn(a: array of byte): string;
	setdebug:	fn(i: int);

	Aattr, Aval, Aquery: con iota;

	Attr: adt {
		tag:	int;
		name:	string;
		val:	string;

		text:	fn(a: self ref Attr): string;
	};

	parseattrs:	fn(s: string): list of ref Attr;
	copyattrs:		fn(l: list of ref Attr): list of ref Attr;
	delattr:	fn(l: list of ref Attr, n: string): list of ref Attr;
	takeattrs:	fn(l: list of ref Attr, names: list of string): list of ref Attr;
	findattr:	fn(l: list of ref Attr, n: string): ref Attr;
	findattrval:	fn(l: list of ref Attr, n: string): string;
	publicattrs:	fn(l: list of ref Attr): list of ref Attr;
	attrtext:	fn(l: list of ref Attr): string;
};
