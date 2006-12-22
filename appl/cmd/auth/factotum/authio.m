Authio: module
{

	Aattr, Aval, Aquery: con iota;

	Attr: adt {
		tag:	int;
		name:	string;
		val:	string;

		text:	fn(a: self ref Attr): string;
	};

	Key: adt {
		attrs:	list of ref Attr;
		secrets:	list of ref Attr;
	#	proto:	Authproto;

		mk:	fn(attrs: list of ref Attr): ref Key;
		text:	fn(k: self ref Key): string;
		safetext:	fn(k: self ref Key): string;
	};

	Fid: adt
	{
		fid:	int;
		pid:	int;
		err:	string;
		attrs:	list of ref Attr;
		write:	chan of (array of byte, Sys->Rwrite);
		read:	chan of (int, Sys->Rread);
	#	proto:	Authproto;
		done:	int;
		ai:	ref Authinfo;
	};

	Rpc: adt {
		r:	ref Fid;
		cmd:	int;
		arg:	array of byte;
		nbytes:	int;
		rc:	chan of (array of byte, string);
	};

	IO: adt {
		f:	ref Fid;
		rpc:	ref Rpc;

		findkey:	fn(io: self ref IO, attrs: list of ref Attr, extra: string): (ref Key, string);
		needkey:	fn(io: self ref IO, attrs: list of ref Attr, extra: string): (ref Key, string);
		read:	fn(io: self ref IO): array of byte;
		readn:	fn(io: self ref IO, n: int): array of byte;
		write:	fn(io: self ref IO, buf: array of byte, n: int): int;
		toosmall:	fn(io: self ref IO, n: int);
		error:	fn(io: self ref IO, s: string);
		ok:	fn(io: self ref IO);
		done:	fn(io: self ref IO, ai: ref Authinfo);
	};

	# need more ... ?
	Authinfo: adt {
		cuid:	string;	# caller id
		suid:	string;	# server id
		cap:	string;	# capability (only valid on server side)
		secret:	array of byte;
	};

	memrandom:	fn(a: array of byte, n: int);
	eqbytes:	fn(a, b: array of byte): int;
	netmkaddr:	fn(addr, net, svc: string): string;
	user:	fn(): string;
	lookattrval:	fn(a: list of ref Attr, n: string): string;
	parseline:	fn(s: string): list of ref Attr;
};

Authproto: module
{
	init:	fn(f: Authio): string;
	interaction:	fn(attrs: list of ref Authio->Attr, io: ref Authio->IO): string;
};
