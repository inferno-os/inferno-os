Wrap : module
{
	PATH : con "/dis/install/wrap.dis";

	FULL, UPD : con iota+1;

	Update : adt {
		desc : string;
		dir : string;
		time : int;
		utime : int;
		bmd5 : ref Bufio->Iobuf;
		typ : int;
	};

	Wrapped : adt {
		name : string;
		root : string;
		tfull : int;
		u : array of Update;
		nu : int;
	};

	init: fn(bio: Bufio);
	openwrap: fn(f : string, d : string, all : int) : ref Wrapped;
	openwraphdr: fn(f : string, d : string, argl : list of string, all : int) : ref Wrapped;
	getfileinfo: fn(w : ref Wrapped, f : string, rdigest : array of byte, wdigest: array of byte, ardigest: array of byte) : (int, int);
	putwrapfile: fn(b : ref Bufio->Iobuf, name : string, time : int, elem : string, file : string, uid : string, gid : string);
	putwrap: fn(b : ref Bufio->Iobuf, name : string, time : int, desc : string, utime : int, pkg : int, uid : string, gid : string);
	md5file: fn(file : string, digest : array of byte) : int;
	md5filea: fn(file : string, digest : array of byte) : int;
	md5sum: fn(b : ref Bufio->Iobuf, digest : array of byte, leng : int) : int;
	md5conv: fn(d : array of byte) : string;
	# utilities
	match: fn(s: string, pre: list of string): int;
	notmatch: fn(s: string, pre: list of string): int;
	memcmp: fn(b1, b2: array of byte, n: int): int;
	end: fn();
	now2string: fn(n: int, flag: int): string;
	string2now: fn(s: string, flag: int): int;
};
