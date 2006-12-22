Rawsexprs: module
{
	PATH:	con "rawsexprs.dis";

	Sexp: adt {
		pick {
		String =>
			s: string;
			hint:	string;
		Binary =>
			data:	array of byte;
			hint: string;
		List =>
			l:	cyclic list of ref Sexp;
		}

		unpack:	fn(a: array of byte): (ref Sexp, array of byte, string);
		text:	fn(e: self ref Sexp): string;
		packedsize:	fn(e: self ref Sexp): int;
		pack:	fn(e: self ref Sexp): array of byte;
	};

	init:	fn();
};

SPKI: module
{
	PATH: con "/dis/lib/spki/spki.dis";

	Hash: adt {
		alg:	string;
		hash:	array of byte;

		sexp:	fn(h: self ref Hash): ref Sexprs->Sexp;
		text:	fn(h: self ref Hash): string;
		eq:	fn(h1: self ref Hash, h2: ref Hash): int;
	};

	Key: adt {
		pk:	ref Keyring->PK;	# either pk/sk or hash might be nil
		sk:	ref Keyring->SK;
		nbits:	int;
		halg:	string;
		hash:	ref Hash;

		hashed:	fn(k: self ref Key, alg: string): array of byte;
		sigalg:	fn(k: self ref Key): string;
		text:	fn(k: self ref Key): string;
		sexp:	fn(k: self ref Key): ref Sexprs->Sexp;
		eq:	fn(k1: self ref Key, k2: ref Key): int;
	};

	Name: adt {
		principal:	ref Key;
		names:	list of string;

		isprincipal:	fn(n: self ref Name): int;
		local:	fn(n: self ref Name): ref Name;
		islocal:	fn(n: self ref Name): int;
		isprefix:	fn(n1: self ref Name, n2: ref Name): int;
		text:	fn(n: self ref Name): string;
		sexp:	fn(n: self ref Name): ref Sexprs->Sexp;
		eq:	fn(n1: self ref Name, n2: ref Name): int;
	};

	Cert: adt {
		e:	ref Sexprs->Sexp;	# S-expression, if originally parsed
		issuer:	ref Name;
		subject:	ref Subject;
		valid:	ref Valid;
		pick {
		A or KH or O =>	# auth, keyholder or object
			delegate:	int;
			tag:	ref Sexprs->Sexp;
		N =>	# name
		}

		text:	fn(c: self ref Cert): string;
		sexp:	fn(c: self ref Cert): ref Sexprs->Sexp;
	};

	# the pick might move to a more general `Principal' structure,
	# allowing compound and quoting principals
	Subject: adt {
		pick{
		P =>
			key:	ref Key;
		N =>
			name:	ref Name;
		O =>
			hash:	ref Hash;
		KH =>
			holder:	ref Name;
		T =>
			k, n:	int;
			subs:	cyclic list of ref Subject;
		}

		eq:	fn(s1: self ref Subject, s2: ref Subject): int;
		principal:	fn(s: self ref Subject): ref Key;
		text:	fn(s: self ref Subject): string;
		sexp:	fn(s: self ref Subject): ref Sexprs->Sexp;
	};

	Principal: adt[T] {
		pick{
		N =>
			name:	ref Name;
		Q =>
			quoter:	T;
			quotes:	cyclic ref Principal;
		}
	};

	Signature: adt {
		hash:	ref Hash;
		key:	ref Key;	# find by hash if necessary
		sa:	string;
		sig:	list of (string, array of byte);

		algs:	fn(s: self ref Signature): (string, string, string);
		sexp:	fn(s: self ref Signature): ref Sexprs->Sexp;
		text:	fn(s: self ref Signature): string;
	};

	Seqel: adt {
		pick{
		C =>
			c: ref Cert;
		K =>
			k: ref Key;
		O =>
			op: string;
			args: list of ref Sexprs->Sexp;
		S =>
			sig: ref Signature;
		RV =>	# <reval>
			ok:	list of (string, string);
			onetime:	array of byte;
			valid:	ref Valid;
		CRL =>
			bad:	list of (string, string);
			valid:	ref Valid;
		Delta =>
			hash:	string;
			bad:	list of (string, string);
			valid:	ref Valid;
		E =>
			exp:	ref Sexprs->Sexp;
		}

		text:	fn(se: self ref Seqel): string;
	};

	Valid: adt {
		notbefore:	string;
		notafter:	string;

		intersect:	fn(a: self Valid, b: Valid): (int, Valid);
		text:	fn(a: self Valid): string;
		sexp:	fn(a: self Valid): ref Sexprs->Sexp;
	};

	Toplev: adt {
		pick {
		C =>
			v:	ref Cert;
		Sig =>
			v:	ref Signature;
		K =>
			v:	ref Key;
		Seq =>
			v:	list of ref Seqel;
		}
	};

	init:	fn();

	# parse structures
	parse:	fn(s: ref Sexprs->Sexp): (ref Toplev, string);
	parseseq:	fn(s: ref Sexprs->Sexp): list of ref Seqel;
	parsecert:	fn(s: ref Sexprs->Sexp): ref Cert;
	parsesig:	fn(s: ref Sexprs->Sexp): ref Signature;
	parsename:	fn(s: ref Sexprs->Sexp): ref Name;
	parsekey:	fn(s: ref Sexprs->Sexp): ref Key;
	parsehash:	fn(s: ref Sexprs->Sexp): ref Hash;
	parsecompound:	fn(s: ref Sexprs->Sexp): ref Name;
	parsevalid:	fn(s: ref Sexprs->Sexp): ref Valid;

	# signature checking
	checksig:	fn(c: ref Cert, sig: ref Signature): string;
	sig2icert:	fn(sig: ref Signature, signer: string, exp: int): ref Keyring->Certificate;

	# tags
	maketag:	fn(e: ref Sexprs->Sexp): ref Sexprs->Sexp;
	tagintersect:	fn(t1: ref Sexprs->Sexp, t2: ref Sexprs->Sexp): ref Sexprs->Sexp;
	tagimplies:	fn(t1: ref Sexprs->Sexp, t2: ref Sexprs->Sexp): int;

	# hash canonical s-expression
	hashbytes:	fn(a: array of byte, alg: string): array of byte;
	hashexp:	fn(e: ref Sexprs->Sexp, alg: string): array of byte;

	# convert between date and time strings and Inferno form
	date2epoch:	fn(s: string): int;	# YYYY-MM-DD_HH:MM:SS
	epoch2date:	fn(t: int): string;
	time2secs:	fn(s: string): int;	# HH:MM:SS
	secs2time:	fn(t: int): string;

	# debugging
	dump:	fn(s: string, a: array of byte);
};

Proofs: module
{
	Proof: adt {
		n:	int;

		parse:	fn(s: string): ref Proof;
		sexp:	fn(p: self ref Proof): ref Sexprs->Sexp;
		text:	fn(p: self ref Proof): string;
	};

	init:	fn(): string;
};

Verifier: module
{
	PATH:	con "/dis/lib/spki/verifier.dis";

	Speaksfor: adt {
		subject:	ref SPKI->Subject;
		name:	ref SPKI->Name;
		regarding:	ref Sexprs->Sexp;
		valid:	ref SPKI->Valid;
	};

	init:	fn();
	verify:	fn(seq: list of ref SPKI->Seqel): (ref Speaksfor, list of ref SPKI->Seqel, string);
};
