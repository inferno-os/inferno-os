Venti: module {
	PATH:	con "/dis/lib/venti.dis";
	Scoresize:		con 20;
	Maxstringsize:	con 1000;
	Authsize:		con  1024;  	# size of auth group - in bits - must be multiple of 8	
	Maxfragsize:	con 9*1024;

	Cryptostrengthnone,
	Cryptostrengthauth,
	Cryptostrengthweak,
	Cryptostrengthstrong:	con iota;

	Cryptonone,
	CryptoSSL3,
	CryptoTLS1,
	Cryptomax:	con iota;

	Codecnone,
	Codecdeflate,
	CodecThwack,
	Codecmax:	con iota;

	Terror,		# not used
	Rerror,
	Tping,
	Rping,
	Thello,
	Rhello,
	Tgoodbye,
	Rgoodbye,	# not used
	Tauth0,
	Rauth0,
	Tauth1,
	Rauth1,
	Tread,
	Rread,
	Twrite,
	Rwrite,
	Tsync,
	Rsync,
	Tmax:		con iota;

	# versions
	Version01,
	Version02:	con iota + 1;

	# Lump Types
	Errtype,		# illegal

	Roottype,
	Dirtype,
	Pointertype0,
	Pointertype1,
	Pointertype2,
	Pointertype3,
	Pointertype4,
	Pointertype5,
	Pointertype6,
	Pointertype7,		# not used
	Pointertype8,		# not used
	Pointertype9,		# not used
	Datatype,

	Maxtype:		con iota;

	# Dir Entry flags
	Entryactive:	con (1<<0);			# entry is in use
	Entrydir:		con (1<<1);			# a directory
	Entrydepthshift: con 2;				# shift for pointer depth
	Entrydepthmask: con (16r7<<2);		# mask for pointer depth
	Entrylocal: con (1<<5);				# used for local storage: should not be set for venti blocks

	Maxlumpsize:	con 56 * 1024;
	Pointerdepth:	con 7;
	Entrysize:		con 40;
	Rootsize:		con 300;
	Rootversion:	con 2;

	Maxfilesize:	con (big 1 << 48) - big 1;

	Vmsg: adt {
		istmsg:	int;
		tid:		int;
		pick {
		Thello =>
			version:	string;
			uid:		string;
			cryptostrength:	int;
			cryptos:	array of byte;
			codecs:	array of byte;
		Rhello =>
			sid:		string;
			crypto:	int;
			codec:	int;
		Tping =>
		Rping =>
		Tread =>
			score:	Score;
			etype:	int;
			n:		int;
		Rread =>
			data:		array of byte;
		Twrite =>
			etype:	int;
			data:		array of byte;
		Rwrite =>
			score:	Score;
		Tsync =>
		Rsync =>
		Tgoodbye =>
		Rerror =>
			e:		string;
		}
		read:			fn(fd: ref Sys->FD): (ref Vmsg, string);
		unpack:		fn(a: array of byte): (int, ref Vmsg);
		pack:		fn(nil: self ref Vmsg): array of byte;
		packedsize:	fn(nil: self ref Vmsg): int;
		text:			fn(nil: self ref Vmsg): string;
	};

	Root: adt {
		version:	int;
		name:	string;
		rtype:	string;
		score:	Venti->Score;		# to a Dir block
		blocksize:	int;				# maximum block size
		prev:		ref Venti->Score;		# last root block

		pack:	fn(r: self ref Root): array of byte;
		unpack:	fn(d: array of byte): ref Root;
	};

	Entry: adt {
		gen:		int;		# generation number (XXX should be unsigned)
		psize:	int;		# pointer block size
		dsize:	int;		# data block size
		depth:	int;		# unpacked from flags
		flags:	int;
		size:		big;		# (XXX should be unsigned)
		score:	Venti->Score;

		pack:	fn(e: self ref Entry): array of byte;
		unpack:	fn(d: array of byte): ref Entry;
	};
	Score: adt {
		a: array of byte;
		eq:		fn(a: self Score, b: Score): int;
		text:		fn(a: self Score): string;
		parse:	fn(s: string): (int, Score);
		zero:		fn(): Score;
	};
	Session: adt {
		fd:		ref Sys->FD;
		version:	string;

		new:		fn(fd: ref Sys->FD): ref Session;
		read:		fn(s: self ref Session, score: Venti->Score, etype: int, maxn: int): array of byte;
		write:	fn(s: self ref Session, etype: int, buf: array of byte): (int, Venti->Score);
		sync:	fn(s: self ref Session): int;
		rpc:		fn(s: self ref Session, m: ref Vmsg): (ref Vmsg, string);
	};
	init:	fn();
};
