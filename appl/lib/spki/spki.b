implement SPKI;

#
# Copyright © 2004 Vita Nuova Holdings Limited
#
# To do:
#	- diagnostics
#	- support for dsa
#	- finish the TO DO

include "sys.m";
	sys: Sys;

include "daytime.m";
	daytime: Daytime;

include "keyring.m";
	kr: Keyring;
	IPint, Certificate, PK, SK: import kr;

include "security.m";

include "bufio.m";

include "sexprs.m";
	sexprs: Sexprs;
	Sexp: import sexprs;

include "spki.m";

include "encoding.m";
	base16: Encoding;
	base64: Encoding;

debug: con 0;

init()
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	daytime = load Daytime Daytime->PATH;
	sexprs = load Sexprs Sexprs->PATH;
	base16 = load Encoding Encoding->BASE16PATH;
	base64 = load Encoding Encoding->BASE64PATH;

	sexprs->init();
}

#
# parse SPKI structures
#

parse(e: ref Sexp): (ref Toplev, string)
{
	if(e == nil)
		return (nil, "nil expression");
	if(!e.islist())
		return (nil, "list expected");
	case e.op() {
	"cert" =>
		if((c := parsecert(e)) != nil)
			return (ref Toplev.C(c), nil);
		return (nil, "bad certificate syntax");
	"signature" =>
		if((s := parsesig(e)) != nil)
			return (ref Toplev.Sig(s), nil);
		return (nil, "bad signature syntax");
	"public-key" or "private-key" =>
		if((k := parsekey(e)) != nil)
			return (ref Toplev.K(k), nil);
		return (nil, "bad public-key syntax");
	"sequence" =>
		if((els := parseseq(e)) != nil)
			return (ref Toplev.Seq(els), nil);
		return (nil, "bad sequence syntax");
	* =>
		return (nil, sys->sprint("unknown operation: %#q", e.op()));
	}
}

parseseq(e: ref Sexp): list of ref Seqel
{
	l := mustbe(e, "sequence");
	if(l == nil)
		return nil;
	rl: list of ref Seqel;
	for(; l != nil; l = tl l){
		se := hd l;
		case se.op() {
		"cert" =>
			cert := parsecert(se);
			if(cert == nil)
				return nil;
			rl = ref Seqel.C(cert) :: rl;
		"do" =>
			el := se.args();
			if(el == nil)
				return nil;
			op := (hd el).astext();
			if(op == nil)
				return nil;
			rl = ref Seqel.O(op, tl el) :: rl;
		"public-key" =>
			k := parsekey(se);
			if(k == nil)
				return nil;
			rl = ref Seqel.K(k) :: rl;
		"signature" =>
			sig := parsesig(se);
			if(sig == nil)
				return nil;
			rl = ref Seqel.S(sig) :: rl;
		* =>
			rl = ref Seqel.E(se) :: rl;
		}
	}
	return rev(rl);
}

parsecert(e: ref Sexp): ref Cert
{
	# "(" "cert" <version>? <cert-display>? <issuer> <issuer-loc>? <subject> <subject-loc>?
	#	<deleg>? <tag> <valid>? <comment>? ")"
	# elements can appear in any order in a top-level item, though the one above is conventional
	# the original s-expression is also retained for later use by the caller, for instance in signature verification

	l := mustbe(e, "cert");
	if(l == nil)
		return nil;
	delegate := 0;
	issuer: ref Name;
	subj: ref Subject;
	tag: ref Sexp;
	valid: ref Valid;
	for(; l != nil; l = tl l){
		t := (hd l).op();
		case t {
		"version" or "display" or "issuer-info" or "subject-info" or "comment" =>
			;	# skip
		"issuer" =>
			# <principal> | <name> [via issuer-name]
			if(issuer != nil)
				return nil;
			ie := onlyarg(hd l);
			if(ie == nil)
				return nil;
			issuer = parsecompound(ie);
			if(issuer == nil)
				return nil;
		"subject" =>
			#    <subject>:: "(" "subject" <subj-obj> ")" ;
			if(subj != nil)
				return nil;
			se := onlyarg(hd l);
			if(se == nil)
				return nil;
			subj = parsesubjobj(se);
			if(subj == nil)
				return nil;
		"propagate" =>
			if(delegate)
				return nil;
			delegate = 1;
		"tag" =>
			if(tag != nil)
				return nil;
			tag = maketag(hd l);	# can safely leave (tag ...) operation in place
		"valid" =>
			if(valid != nil)
				return nil;
			valid = parsevalid(hd l);
			if(valid == nil)
				return nil;
		* =>
			sys->print("cert component: %q unknown/ignored\n", t);
		}
	}
	if(issuer == nil || subj == nil)
		return nil;
	pick s := subj {
	KH =>
		return ref Cert.KH(e, issuer, subj, valid, delegate, tag);
	O =>
		return ref Cert.O(e, issuer, subj, valid, delegate, tag);
	* =>
		if(issuer.isprincipal())
			return ref Cert.A(e, issuer, subj, valid, delegate, tag);
		return ref Cert.N(e, issuer, subj, valid);
	}
}

parsesubjobj(e: ref Sexp): ref Subject
{
	#  <subj-obj>:: <principal> | <name> | <obj-hash> | <keyholder> | <subj-thresh> ;
	case e.op() {
	"name" or "hash" or "public-key" =>
		name := parsecompound(e);
		if(name == nil)
			return nil;
		if(name.names == nil)
			return ref Subject.P(name.principal);
		return ref Subject.N(name);

	"object-hash" =>
		e = onlyarg(e);
		if(e == nil)
			return nil;
		hash := parsehash(e);
		if(hash == nil)
			return nil;
		return ref Subject.O(hash);

	"keyholder" =>
		e = onlyarg(e);
		if(e == nil)
			return nil;
		name := parsecompound(e);
		if(name == nil)
			return nil;
		return ref Subject.KH(name);

	"k-of-n" =>
		el := e.args();
		m := len el;
		if(m < 2)
			return nil;
		k := intof(hd el);
		n := intof(hd tl el);
		if(k < 0 || n < 0 || k > n || n != m-2)
			return nil;
		el = tl tl el;
		sl: list of ref Subject;
		for(; el != nil; el = tl el){
			o := parsesubjobj(hd el);
			if(o == nil)
				return nil;
			sl = o :: sl;
		}
		return ref Subject.T(k, n, rev(sl));

	* =>
		return nil;
	}
}

parsesig(e: ref Sexp): ref Signature
{
	# <signature>:: "("  "signature" <hash> <principal> <sig-val> ")"
	# <sig-val>:: "(" <pub-sig-alg-id> <sig-params> ")"
	# <pub-sig-alg-id>:: "rsa-pkcs1-md5" | "rsa-pkcs1-sha1" | "rsa-pkcs1" | "dsa-sha1" | <uri>
	# <sig-params>:: <byte-string> | <s-expr>+

	l := mustbe(e, "signature");
	if(len l < 3)
		return nil;
	# signature hash key sig
	hash := parsehash(hd l);
	k := parseprincipal(hd tl l);
	if(hash == nil || k == nil)
		return nil;
	val := hd tl tl l;
	if(!val.islist()){	# not in grammar but examples paper uses it
		sigalg: string;
		if(k != nil)
			sigalg = k.sigalg();
		return ref Signature(hash, k, sigalg, (nil, val.asdata()) :: nil);
	}
	sigalg := val.op();
	if(sigalg == nil)
		return nil;
	rl: list of (string, array of byte);
	for(els := val.args(); els != nil; els = tl els){
		g := hd els;
		if(g.islist()){
			arg := onlyarg(g);
			if(arg == nil)
				return nil;
			rl = (g.op(), arg.asdata()) :: rl;
		}else
			rl = (nil, g.asdata()) :: rl;
	}
	return ref Signature(hash, k, sigalg, revt(rl));
}

parsecompound(e: ref Sexp): ref Name
{
	if(e == nil)
		return nil;
	case e.op() {
	"name" =>
		return parsename(e);
	"public-key" or "hash" =>
		k := parseprincipal(e);
		if(k == nil)
			return nil;
		return ref Name(k, nil);
	* =>
		return nil;
	}
}

parsename(e: ref Sexp): ref Name
{
	l := mustbe(e, "name");
	if(l == nil)
		return nil;
	k: ref Key;
	if((hd l).islist()){	# must be principal: pub key or hash of key
		k = parseprincipal(hd l);
		if(k == nil)
			return nil;
		l = tl l;
	}
	names: list of string;
	for(; l != nil; l = tl l){
		s := (hd l).astext();
		if(s == nil)
			return nil;
		names = s :: names;
	}
	return ref Name(k, rev(names));
}

parseprincipal(e: ref Sexp): ref Key
{
	case e.op() {
	"public-key" or "private-key" =>
		return parsekey(e);
	"hash" =>
		hash := parsehash(e);
		if(hash == nil)
			return nil;
		return ref Key(nil, nil, 0, nil, nil, hash::nil);
	* =>
		return nil;
	}
}

parsekey(e: ref Sexp): ref Key
{
	issk := 0;
	l := mustbe(e, "public-key");
	if(l == nil){
		l = mustbe(e, "private-key");
		if(l == nil)
			return nil;
		issk = 1;
	}
	kind := (hd l).op();
	(nf, fld) := sys->tokenize(kind, "-");
	if(nf < 1)
		return nil;
	alg := hd fld;
	if(nf > 1)
		enc := hd tl fld;		# signature hash encoding
	mha := "sha1";
	if(nf > 2)
		mha = hd tl tl fld;	# signature hash algorithm
	kl := (hd l).args();
	if(kl == nil)
		return nil;
	els: list of (string, ref IPint);
	for(; kl != nil; kl = tl kl){
		t := (hd kl).op();
		a := onlyarg(hd kl).asdata();
		if(a == nil)
			return nil;
		ip := IPint.bebytestoip(a);
		if(ip == nil)
			return nil;
		els = (t, ip) :: els;
	}
	krp := ref Keyrep.PK(alg, "sdsi", els);
	(pk, nbits) := krp.mkpk();
	if(pk == nil){
		sys->print("can't convert public-key\n");
		return nil;
	}
	sk: ref Keyring->SK;
	if(issk){
		krp = ref Keyrep.SK(alg, "sdsi", els);
		sk = krp.mksk();
		if(sk == nil){
			sys->print("can't convert private-key\n");
			return nil;
		}
	}
#(ref Key(pk,nil,"md5",nil,nil)).hashed("md5");		# TEST
	return ref Key(pk, sk, nbits, mha, enc, nil);
}

parsehash(e: ref Sexp): ref Hash
{
	# "(" "hash" <hash-alg-name> <hash-value> <uris>? ")"
	l := mustbe(e, "hash");
	if(len l < 2)
		return nil;
	return ref Hash((hd l).astext(), (hd tl l).asdata());
}

parsevalid(e: ref Sexp): ref Valid
{
	l := mustbe(e, "valid");
	if(l == nil)
		return nil;
	el: list of ref Sexp;
	notbefore, notafter: string;
	(el, l) = isita(l, "not-before");
	if(el != nil && (notafter = ckdate((hd el).astext())) == nil)
		return nil;
	(el, l) = isita(l, "not-after");
	if(el != nil && (notafter = ckdate((hd el).astext())) == nil)
		return nil;
	for(;;){
		(el, l) = isita(l, "online");
		if(el == nil)
			break;
	}
	if(el != nil)
		return nil;
	return ref Valid(notbefore, notafter);
}

isnumeric(s: string): int
{
	for(i := 0; i < len s; i++)
		if(!(s[i]>='0' && s[i]<='9'))
			return 0;
	return s != nil;
}

ckdate(s: string): string
{
	if(date2epoch(s) < 0)	# TO DO: prefix/suffix tests
		return nil;
	return s;
}

Toplev.sexp(top: self ref Toplev): ref Sexp
{
	pick t := top {
	C =>
		return t.v.sexp();
	Sig =>
		return t.v.sexp();
	K =>
		return t.v.sexp();
	Seq =>
		rels := rev(t.v);
		els: list of ref Sexp;
		for(; rels != nil; rels = tl rels)
			els = (hd rels).sexp() :: els;
		return ref Sexp.List(ref Sexp.String("sequence", nil) :: els);
	* =>
		raise "unexpected spki type";
	}
}

Toplev.text(top: self ref Toplev): string
{
	return top.sexp().text();
}

Seqel.sexp(se: self ref Seqel): ref Sexp
{
	pick r := se {
	C =>
		return r.c.sexp();
	K =>
		return r.k.sexp();
	O =>
		return ref Sexp.List(ref Sexp.String("do",nil) :: ref Sexp.String(r.op,nil) :: r.args);
	S =>
		return r.sig.sexp();
	E =>
		return r.exp;
	* =>
		raise "unsupported value";
	}
}

Seqel.text(se: self ref Seqel): string
{
	pick r := se {
	C =>
		return r.c.text();
	K =>
		return r.k.text();
	O =>
		return se.sexp().text();
	S =>
		return r.sig.text();
	E =>
		return r.exp.text();
	* =>
		raise "unsupported value";
	}
}

isita(l: list of ref Sexp, s: string): (list of ref Sexp, list of ref Sexp)
{
	if(l == nil)
		return (nil, nil);
	e := hd l;
	if(e.islist() && e.op() == s)
		return (e.args(), tl l);
	return (nil, l);
}

intof(e: ref Sexp): int
{
	# int should be plenty; don't need big
	pick s := e {
	List =>
		return -1;
	Binary =>
		if(len s.data > 4)
			return -1;
		v := 0;
		for(i := 0; i < len s.data; i++)
			v = (v<<8) | int s.data[i];
		return v;
	String =>
		if(s.s == nil || !(s.s[0]>='0' && s.s[0]<='9'))
			return -1;
		return int s.s;
	}
}

onlyarg(e: ref Sexp): ref Sexp
{
	l := e.args();
	if(l == nil || tl l != nil)
		return nil;
	return hd l;
}

mustbe(e: ref Sexp, kind: string): list of ref Sexp
{
	if(e != nil && e.islist() && e.op() == kind)
		return e.args();
	return nil;
}

checksig(c: ref Cert, sig: ref Signature): string
{
	if(c.e == nil)
		return "missing S-expression for certificate";
	if(sig.key == nil)
		return "missing key for signature";
	if(sig.hash == nil)
		return "missing hash for signature";
	if(sig.sig == nil)
		return "missing signature value";
	pk := sig.key.pk;
	if(pk == nil)
		return "missing Keyring->PK for signature";	# TO DO (need a way to tell that key was just a hash)
#rsacomp((hd sig.sig).t1, sig.key);
#sys->print("nbits= %d\n", sig.key.nbits);
	(alg, enc, hashalg) := sig.algs();
	if(alg == nil)
		return "unspecified signature algorithm";
	if(hashalg == nil)
		hashalg = "md5";	# TO DO?
	hash := hashbytes(c.e.pack(), hashalg);
	if(hash == nil)
		return "unknown hash algorithm "+hashalg;
	if(enc == nil)
		h := hash;
	else if(enc == "pkcs" || enc == "pkcs1")
		h = pkcs1_encode(hashalg, hash, (sig.key.nbits+7)/8);
	else
		return "unknown encoding algorithm "+enc;
#dump("check/hashed", hash);
#dump("check/h", h);
	ip := IPint.bebytestoip(h);
	isig := sig2icert(sig, "sdsi", 0);
	if(isig == nil)
		return "couldn't convert SPKI signature to Keyring form";
	if(!kr->verifym(pk, isig, ip))
		return "signature does not match";
	return nil;
}

signcert(c: ref Cert, sigalg: string, key: ref Key): (ref Signature, string)
{
	if(c.e == nil){
		c.e = c.sexp();
		if(c.e == nil)
			return (nil, "bad input certificate");
	}
	return signbytes(c.e.pack(), sigalg, key);
}

#
# might be useful to have a separate `signhash' for cases where the data was hashed elsewhere
#
signbytes(data: array of byte, sigalg: string, key: ref Key): (ref Signature, string)
{
	if(key.sk == nil)
		return (nil, "missing Keyring->SK for signature");
	pubkey := ref *key;
	pubkey.sk = nil;
	sig := ref Signature(nil, pubkey, sigalg, nil);	# ref Hash, key, alg, sig: list of (string, array of byte)
	(alg, enc, hashalg) := sigalgs(sigalg);
	if(alg == nil)
		return (nil, "unspecified signature algorithm");
	if(hashalg == nil)
		hashalg = "md5";	# TO DO?
	hash := hashbytes(data, hashalg);
	if(hash == nil)
		return (nil, "unknown hash algorithm "+hashalg);
	if(enc == nil)
		h := hash;
	else if(enc == "pkcs" || enc == "pkcs1")
		h = pkcs1_encode(hashalg, hash, (sig.key.nbits+7)/8);
	else
		return (nil, "unknown encoding algorithm "+enc);
#dump("sign/hashed", hash);
#dump("sign/h", h);
	sig.hash = ref Hash(hashalg, hash);
	ip := IPint.bebytestoip(h);
	icert := kr->signm(key.sk, ip, hashalg);
	if(icert == nil)
		return (nil, "signature failed");	# can't happen?
	(nil, nil, nil, vals) := icert2els(icert);
	if(vals == nil)
		return (nil, "couldn't extract values from Keyring Certificate");
	l: list of (string, array of byte);
	for(; vals != nil; vals = tl vals){
		(n, v) := hd vals;
		l = (f2s("rsa", n), v) :: l;
	}
	sig.sig = revt(l);
	return (sig, nil);
}

hashexp(e: ref Sexp, alg: string): array of byte
{
	return hashbytes(e.pack(), alg);
}

hashbytes(a: array of byte, alg: string): array of byte
{
	hash: array of byte;
	case alg {
	"md5" =>
		hash = array[Keyring->MD5dlen] of byte;
		kr->md5(a, len a, hash, nil);
	"sha" or "sha1" =>
		hash = array[Keyring->SHA1dlen] of byte;
		kr->sha1(a, len a, hash, nil);
	* =>
		raise "Spki->hashbytes: unknown algorithm: "+alg;
	}
	return hash;
}

# trim mpint and add leading zero byte if needed to ensure value is unsigned
pre0(a: array of byte): array of byte
{
	for(i:=0; i<len a-1; i++)
		if(a[i] != a[i+1] && (a[i] != byte 0 || (int a[i+1] & 16r80) != 0))
			break;
	if(i > 0)
		a = a[i:];
	if(len a < 1 || (int a[0] & 16r80) == 0)
		return a;
	b := array[len a + 1] of byte;
	b[0] = byte 0;
	b[1:] = a;
	return b;
}

dump(s: string, a: array of byte)
{
	s = sys->sprint("%s [%d]: ", s, len a);
	for(i := 0; i < len a; i++)
		s += sys->sprint(" %.2ux", int a[i]);
	sys->print("%s\n", s);
}

Signature.algs(sg: self ref Signature): (string, string, string)
{
	return sigalgs(sg.sa);
}

# sig[-[enc-]hash]
sigalgs(alg: string): (string, string, string)
{
	(nf, flds) := sys->tokenize(alg, "-");
	if(nf >= 3)
		return (hd flds, hd tl flds, hd tl tl flds);
	if(nf >= 2)
		return (hd flds, nil, hd tl flds);
	if(nf >= 1)
		return (hd flds, nil, nil);
	return (nil, nil, nil);
}

Signature.sexp(sg: self ref Signature): ref Sexp
{
	sv: ref Sexp;
	if(len sg.sig != 1){
		l: list of ref Sexp;
		for(els := sg.sig; els != nil; els = tl els){
			(op, val) := hd els;
			if(op != nil)
				l = ref Sexp.List(ref Sexp.String(op,nil) :: ref Sexp.Binary(val,nil) :: nil) :: l;
			else
				l =  ref Sexp.Binary(val,nil) :: l;
		}
		sv = ref Sexp.List(rev(l));
	}else
		sv = ref Sexp.Binary((hd sg.sig).t1, nil);	# no list if signature has one component
	if(sg.sa != nil)
		sv = ref Sexp.List(ref Sexp.String(sg.sa,nil) :: sv :: nil);
	return ref Sexp.List(ref Sexp.String("signature",nil) :: sg.hash.sexp() :: sg.key.sexp() ::
		sv :: nil);
}

Signature.text(sg: self ref Signature): string
{
	if(sg == nil)
		return nil;
	return sg.sexp().text();
}

Hash.sexp(h: self ref Hash): ref Sexp
{
	return ref Sexp.List(ref Sexp.String("hash",nil) ::
		ref Sexp.String(h.alg, nil) :: ref Sexp.Binary(h.hash,nil) :: nil);
}

Hash.text(h: self ref Hash): string
{
	return h.sexp().text();
}

Hash.eq(h1: self ref Hash, h2: ref Hash): int
{
	if(h1 == h2)
		return 1;
	if(h1 == nil || h2 == nil || h1.alg != h2.alg)
		return 0;
	return cmpbytes(h1.hash, h2.hash) == 0;
}

Valid.intersect(a: self Valid, b: Valid): (int, Valid)
{
	c: Valid;
	if(a.notbefore < b.notbefore)
		c.notbefore = b.notbefore;
	else
		c.notbefore = a.notbefore;
	if(a.notafter == nil)
		c.notafter = b.notafter;
	else if(b.notafter == nil || a.notafter < b.notafter)
		c.notafter = a.notafter;
	else
		c.notafter = b.notafter;
	if(c.notbefore > c.notafter)
		return (0, (nil, nil));
	return (1, c);
}

Valid.text(a: self Valid): string
{
	na, nb: string;
	if(a.notbefore != nil)
		nb = " (not-before \""+a.notbefore+"\")";
	if(a.notafter != nil)
		na = " (not-after \""+a.notafter+"\")";
	return sys->sprint("(valid%s%s)", nb, na);
}

Valid.sexp(a: self Valid): ref Sexp
{
	nb, na: ref Sexp;
	if(a.notbefore != nil)
		nb = ref Sexp.List(ref Sexp.String("not-before",nil) :: ref Sexp.String(a.notbefore,nil) :: nil);
	if(a.notafter != nil)
		na = ref Sexp.List(ref Sexp.String("not-after",nil) :: ref Sexp.String(a.notafter,nil) :: nil);
	if(nb == nil && na == nil)
		return nil;
	return ref Sexp.List(ref Sexp.String("valid",nil) :: nb :: na :: nil);
}

Cert.text(c: self ref Cert): string
{
	if(c == nil)
		return "nil";
	v: string;
	pick d := c {
	A or KH or O =>
		if(d.tag != nil)
			v += " "+d.tag.text();
	}
	if(c.valid != nil)
		v += " "+(*c.valid).text();
	return sys->sprint("(cert (issuer %s) (subject %s)%s)", c.issuer.text(), c.subject.text(), v);
}

Cert.sexp(c: self ref Cert): ref Sexp
{
	if(c == nil)
		return nil;
	if(c.e != nil)
		return c.e;
	ds, tag: ref Sexp;
	pick d := c {
	N =>
	A or KH or O =>
		if(d.delegate)
			ds = ref Sexp.List(ref Sexp.String("propagate",nil) :: nil);
		tag = d.tag;
	}
	if(c.valid != nil)
		vs := (*c.valid).sexp();
	s := ref Sexp.List(ref Sexp.String("cert",nil) ::
		ref Sexp.List(ref Sexp.String("issuer",nil) :: c.issuer.sexp() :: nil) ::
		c.subject.sexp() ::
		ds ::
		tag ::
		vs ::
		nil);
	return s;
}

Subject.principal(s: self ref Subject): ref Key
{
	pick r := s {
	P =>
		return r.key;
	N =>
		return r.name.principal;
	KH =>
		return r.holder.principal;
	O =>
		return nil;	# TO DO: need cache of hashed keys
	* =>
		return nil;	# TO DO? (no particular principal for threshold)
	}
}

Subject.text(s: self ref Subject): string
{
	pick r := s {
	P =>
		return r.key.text();
	N =>
		return r.name.text();
	KH =>
		return sys->sprint("(keyholder %s)", r.holder.text());
	O =>
		return sys->sprint("(object-hash %s)", r.hash.text());
	T =>
		return s.sexp().text();	# easy way out
	}
}

Subject.sexp(s: self ref Subject): ref Sexp
{
	e: ref Sexp;
	pick r := s {
	P =>
		e = r.key.sexp();
	N =>
		e = r.name.sexp();
	KH =>
		e = ref Sexp.List(ref Sexp.String("keyholder",nil) :: r.holder.sexp() :: nil);
	O =>
		e = ref Sexp.List(ref Sexp.String("object-hash",nil) :: r.hash.sexp() :: nil);
	T =>
		sl: list of ref Sexp;
		for(subs := r.subs; subs != nil; subs = tl subs)
			sl = (hd subs).sexp() :: sl;
		e = ref Sexp.List(ref Sexp.String("k-of-n",nil) ::
			ref Sexp.String(string r.k,nil) :: ref Sexp.String(string r.n,nil) :: rev(sl));
	* =>
		return nil;
	}
	return ref Sexp.List(ref Sexp.String("subject",nil) :: e :: nil);
}

Subject.eq(s1: self ref Subject, s2: ref Subject): int
{
	if(s1 == s2)
		return 1;
	if(s1 == nil || s2 == nil || tagof s1 != tagof s2)
		return 0;
	pick r1 := s1 {
	P =>
		pick r2 := s2 {
		P =>
			return r1.key.eq(r2.key);
		}
	N =>
		pick r2 := s2 {
		N =>
			return r1.name.eq(r2.name);
		}
	O =>
		pick r2 := s2 {
		O =>
			return r1.hash.eq(r2.hash);
		}
	KH =>
		pick r2 := s2 {
		KH =>
			return r1.holder.eq(r2.holder);
		}
	T =>
		pick r2 := s2 {
		T =>
			if(r1.k != r2.k || r1.n != r2.n)
				return 0;
			l2 := r2.subs;
			for(l1 := r1.subs; l1 != nil; l1 = tl l1){
				if(l2 == nil || !(hd l1).eq(hd l2))
					return 0;
				l2 = tl l2;
			}
		}
	}
	return 0;
}

Name.isprincipal(n: self ref Name): int
{
	return n.names == nil;
}

Name.local(n: self ref Name): ref Name
{
	if(n.names == nil || tl n.names == nil)
		return n;
	return ref Name(n.principal, hd n.names :: nil);
}

Name.islocal(n: self ref Name): int
{
	return n.names == nil || tl n.names == nil;
}

Name.isprefix(n1: self ref Name, n2: ref Name): int
{
	if(n1 == nil)
		return n2 == nil;
	if(!n1.principal.eq(n2.principal))
		return 0;
	s1 := n1.names;
	s2 := n2.names;
	for(; s1 != nil; s1 = tl s1){
		if(s2 == nil || hd s2 != hd s1)
			return 0;
		s2 = tl s2;
	}
	return 1;
}

Name.text(n: self ref Name): string
{
	if(n.principal == nil)
		s := "$self";
	else
		s = n.principal.text();
	for(nl := n.names; nl != nil; nl = tl nl)
		s += " " + hd nl;
	return "(name "+s+")";
}

Name.sexp(n: self ref Name): ref Sexp
{
	ns: list of ref Sexp;

	if(n.principal != nil)
		is := n.principal.sexp();
	else
		is = ref Sexp.String("$self",nil);
	if(n.names == nil)
		return is;
	for(nl := n.names; nl != nil; nl = tl nl)
		ns = ref Sexp.String(hd nl,nil) :: ns;
	return ref Sexp.List(ref Sexp.String("name",nil) :: is :: rev(ns));
}

Name.eq(a: self ref Name, b: ref Name): int
{
	if(a == b)
		return 1;
	if(a == nil || b == nil)
		return 0;
	if(!a.principal.eq(b.principal))
		return 0;
	nb := b.names;
	for(na := a.names; na != nil; na = tl na){
		if(nb == nil || hd nb != hd na)
			return 0;
		nb = tl nb;
	}
	return nb == nil;
}

Key.public(key: self ref Key): ref Key
{
	if(key.sk != nil){
		pk := ref *key;
		if(pk.pk == nil)
			pk.pk = kr->sktopk(pk.sk);
		pk.sk = nil;
		return pk;
	}
	if(key.pk == nil)
		return nil;
	return key;
}

Key.ishash(k: self ref Key): int
{
	return k.hash != nil && k.sk == nil && k.pk == nil;
}

Key.hashed(key: self ref Key, alg: string): array of byte
{
	e := key.sexp();
	if(e == nil)
		return nil;
	return hashexp(key.sexp(), alg);
}

Key.hashexp(key: self ref Key, alg: string): ref Hash
{
	if(key.hash != nil){
		for(l := key.hash; l != nil; l = tl l){
			h := hd l;
			if(h.alg == alg && h.hash != nil)
				return h;
		}
	}
	hash := key.hashed(alg);
	if(hash == nil)
		return nil;
	h := ref Hash(alg, hash);
	key.hash = h :: key.hash;
	return h;
}

Key.sigalg(k: self ref Key): string
{
	if(k.pk != nil)
		alg := k.pk.sa.name;
	else if(k.sk != nil)
		alg = k.sk.sa.name;
	else
		return nil;
	if(k.halg != nil){
		if(k.henc != nil)
			alg += "-"+k.henc;
		alg += "-"+k.halg;
	}
	return alg;
}

Key.text(k: self ref Key): string
{
	e := k.sexp();
	if(e == nil)
		return sys->sprint("(public-key unknown)");
	return e.text();
}

Key.sexp(k: self ref Key): ref Sexp
{
	if(k.sk == nil && k.pk == nil){
		if(k.hash != nil)
			return (hd k.hash).sexp();
		return nil;
	}
	sort := "public-key";
	els: list of (string, ref IPint);
	if(k.sk != nil){
		krp := Keyrep.sk(k.sk);
		if(krp == nil)
			return nil;
		els = krp.els;
		sort = "private-key";
	}else{
		krp := Keyrep.pk(k.pk);
		if(krp == nil)
			return nil;
		els = krp.els;
	}
	rl: list of ref Sexp;
	for(; els != nil; els = tl els){
		(n, v) := hd els;
		a := pre0(v.iptobebytes());
		rl = ref Sexp.List(ref Sexp.String(f2s("rsa", n),nil) :: ref Sexp.Binary(a,nil) :: nil) :: rl;
	}
	return ref Sexp.List(ref Sexp.String(sort, nil) ::
		ref Sexp.List(ref Sexp.String(k.sigalg(),nil) :: rev(rl)) :: nil);
}

Key.eq(k1: self ref Key, k2: ref Key): int
{
	if(k1 == k2)
		return 1;
	if(k1 == nil || k2 == nil)
		return 0;
	for(hl1 := k1.hash; hl1 != nil; hl1 = tl hl1){
		h1 := hd hl1;
		for(hl2 := k2.hash; hl2 != nil; hl2 = tl hl2){
			h2 := hd hl2;
			if(h1.hash != nil && h1.eq(h2))
				return 1;
		}
	}
	if(k1.pk != nil && k2.pk != nil)
		return kr->pktostr(k1.pk) == kr->pktostr(k2.pk);	# TO DO
	return 0;
}

dec(s: string, i: int, l: int): (int, int)
{
	l += i;
	n := 0;
	for(; i < l; i++){
		c := s[i];
		if(!(c >= '0' && c <= '9'))
			return (-1, 0);
		n = n*10 + (c-'0');
	}
	return (n, l);
}

# accepts at least any valid prefix of a date
date2epoch(t: string): int
{
	# yyyy-mm-dd_hh:mm:ss
	if(len t >= 4 && len t < 19)
		t += "-01-01_00:00:00"[len t-4:];	# extend non-standard short forms
	else if(len t != 19)
		return -1;
	tm := ref Daytime->Tm;
	i: int;
	(tm.year, i) = dec(t, 0, 4);
	if(tm.year < 0 || t[i++] != '-')
		return -1;
	tm.year -= 1900;
	(tm.mon, i) = dec(t, i, 2);
	if(tm.mon <= 0 || t[i++] != '-' || tm.mon > 12)
		return -1;
	tm.mon--;
	(tm.mday, i) = dec(t, i, 2);
	if(tm.mday <= 0 || t[i++] != '_' || tm.mday >= 31)
		return -1;
	(tm.hour, i) = dec(t, i, 2);
	if(tm.hour < 0 || t[i++] != ':' || tm.hour > 23)
		return -1;
	(tm.min, i) = dec(t, i, 2);
	if(tm.min < 0 || t[i++] != ':' || tm.min > 59)
		return -1;
	(tm.sec, i) = dec(t, i, 2);
	if(tm.sec < 0 || tm.sec > 59)	# leap second(s)?
		return -1;
	tm.tzoff = 0;
	return daytime->tm2epoch(tm);
}

epoch2date(t: int): string
{
	tm := daytime->gmt(t);
	return sys->sprint("%.4d-%.2d-%.2d_%.2d:%.2d:%.2d",
		tm.year+1900, tm.mon+1, tm.mday, tm.hour, tm.min, tm.sec);
}

# could use a delta-time function

time2secs(s: string): int
{
	# HH:MM:SS
	if(len s >= 2 && len s < 8)
		s += ":00:00"[len s-2:];	# extend non-standard short forms
	else if(len s != 8)
		return -1;
	hh, mm, ss, i: int;
	(hh, i) = dec(s, 0, 2);
	if(hh < 0 || hh > 24 || s[i++] != ':')
		return -1;
	(mm, i) = dec(s, i, 2);
	if(mm < 0 || mm > 59 || s[i++] != ':')
		return -1;
	(ss, i) = dec(s, i, 2);
	if(ss < 0 || ss > 59)
		return -1;
	return hh*3600 + mm*60 + ss;
}

secs2time(t: int): string
{
	hh := (t/60*60)%24;
	mm := (t%3600)/60;
	ss := t%60;
	return sys->sprint("%.2d:%.2d:%.2d", hh, mm, ss);
}

#
# auth tag intersection as defined by
#	``A Formal Semantics for SPKI'', Jon Howell, David Kotz
#		its proof cases are marked by the roman numerals (I) ... (X)
# with contributions from
#	``A Note on SPKI's Authorisation Syntax'', Olav Bandmann, Mads Dam
#		its AIntersect cases are marked by arabic numerals

maketag(e: ref Sexp): ref Sexp
{
	if(e == nil)
		return e;
	return remake(e.copy());
}

tagimplies(t1: ref Sexp, t2: ref Sexp): int
{
	e := tagintersect(t1, t2);
	if(e == nil)
		return 0;
	return e.eq(t2);
}

Anull, Astar, Abytes, Aprefix, Asuffix, Arange, Alist, Aset: con iota;

tagindex(s: ref Sexp): int
{
	if(s == nil)
		return Anull;
	pick r := s {
	String =>
		return Abytes;
	Binary =>
		return Abytes;
	List =>
		if(r.op() == "*"){
			if(tl r.l == nil)
				return Astar;
			case (hd tl r.l).astext() {
			"prefix" =>	return Aprefix;
			"suffix" =>	return Asuffix;
			"range" =>	return Arange;
			"set" =>	return Aset;
			* =>	return Anull;	# unknown
			}
		}
		return Alist;
	* =>
		return Anull;	# not reached
	}
}

#
# 1	(*) x r = r
# 2	r x (*) = r
# 3	⊥ x r = ⊥
# 4	r x ⊥ = ⊥
# 5	a x a = a  (also a x a' = ⊥)
# 6	a x b = a if a ∈ Val(b)
# 7	a x b = ⊥ if a ∉ Val(b)
# 8	a x (a' r1 ... rn)) = ⊥
# 9	a x (* set r1 ... ri = a ... rn) = a
# 10	a x (* set r1 ... ri = b ... rn) = a, if a ∈ Val(b)
# 11	a x (* set r1 ... ri ... rn)) = ⊥, if neither of above two cases applies
# 12	b x b' = b ∩ b'
# 13	b x (a r1 ... rn) = ⊥
# 14	b x (* set r1 ... rn) = (*set (b x r'[1]) ... (b x r'[m])), for atomic elements in r1, ..., rn
# 15	(a r1 ... rn) x (a r'[1] ... r'[n] r'[n+1] ... r'[m]) = (a (r1 x r'[1]) ... (rn x r'[n]) r'[n+1] ... r'[m]) for m >= n
# 16	(a r1 ... rn) x (a' r'[1] ... r'[m]) = ⊥
# 17	(a r1 ... rn) x (* set r'[1] ... r'[i] ... r'[k]) = (a r1 ... rn) x r'[i], if r'[i] has tag a
# 18	(a r1 ... rn) x (* set r'[1] ... r'[m]) = ⊥, if no r'[i] has tag a
# 19	(* set r1 .. rn) x r, where r is (* set r1'[1] ... r'[m]) = (* set (r1 x r) (r2 x r) ... (rn x r))
#
# nil is used instead of ⊥, which works provided an incoming credential
# with no tag has implicit tag (*)
#

# put operands in order of proof in FSS

swaptag := array[] of {
	(Abytes<<4) | Alist =>	(Alist<<4) | Abytes,	# (IV)

	(Abytes<<4) | Aset =>	(Aset<<4) | Abytes,	# (VI)
	(Aprefix<<4) | Aset =>	(Aset<<4) | Aprefix,	# (VI)
	(Arange<<4) | Aset =>	(Aset<<4) | Arange,	# (VI)
	(Alist<<4) | Aset =>	(Aset<<4) | Alist,	# (VI)
	(Asuffix<<4) | Aset =>	(Aset<<4) | Asuffix,	# (VI)	extension

	(Aprefix<<4) | Abytes =>	(Abytes<<4) | Aprefix,	# (VII)
	(Arange<<4) | Abytes =>	(Abytes<<4) | Arange,	# (VII)
	(Asuffix<<4) | Abytes =>	(Abytes<<4) | Asuffix,	# (VII) extension

	* => 0,
};

tagintersect(t1, t2: ref Sexp): ref Sexp
{
	if(t1 == t2)
		return t1;
	if(t1 == nil || t2 == nil)	# 3, 4; case (I)
		return nil;
	x1 := tagindex(t1);
	x2 := tagindex(t2);
	if(debug){
		sys->print("%#q -> %d\n", t1.text(), x1);
		sys->print("%#q -> %d\n", t2.text(), x2);
	}
	if(x1 == Astar)	# 1; case (II)
		return t2;
	if(x2 == Astar)	# 2; case (II)
		return t1;
	code := (x1 << 4) | x2;	# (a[x]<<4) | a[y] in FSS
	# reorder symmetric cases
	if(code < len swaptag && swaptag[code]){
		(t1, t2) = (t2, t1);
		(x1, x2) = (x2, x1);
		code = swaptag[code];
	}
	case code {
	(Abytes<<4) | Abytes =>	# case (III); 5
		if(t1.eq(t2))
			return t1;

	(Alist<<4) | Abytes =>	# case (IV)
		return nil;

	(Alist<<4) | Alist =>	# case (V); 15-16
		if(t1.op() != t2.op())
			return nil;
		l1 := t1.els();
		l2 := t2.els();
		if(len l1 > len l2){
			(t1, t2) = (t2, t1);
			(l1, l2) = (l2, l1);
		}
		rl: list of ref Sexp;
		for(; l1 != nil; l1 = tl l1){
			x := tagintersect(hd l1, hd l2);
			if(x == nil)
				return nil;
			rl = x :: rl;
			l2 = tl l2;
		}
		for(; l2 != nil; l2 = tl l2)
			rl = hd l2 :: rl;
		return ref Sexp.List(rev(rl));

	(Aset<<4) | Abytes =>	# case (VI); 9-11
		for(el := setof(t1); el != nil; el = tl el){
			e := hd el;
			case tagindex(e) {
			Abytes =>
				if(e.eq(t2))
					return t2;
			Astar =>
				return t2;
			Arange =>
				if(inrange(t2, e))
					return t2;
			Aprefix =>
				if(isprefix(e, t2))
					return t2;
			Asuffix =>
				if(issuffix(e, t2))
					return t2;
			}
		}
		# otherwise null

	(Aset<<4) | Alist =>	# case (VI); 17-18
		o := t2.op();
		for(el := setof(t1); el != nil; el = tl el){
			e := hd el;
			if(e.islist() && e.op() == o || tagindex(e) == Astar)
				return tagintersect(e, t2);
		}
		# otherwise null

	(Aset<<4) | Aprefix or	# case (VI); 14
	(Aset<<4) | Arange or	# case (VI); 14
		# for Aprefix or Arange, could restrict els of t1 to atomic elements (sets A and B)
		# here, following rule 14, but we'll let tagintersect sort it out in the general case below
	(Aset<<4) | Aset =>	# case (VI); 19
		rl: list of ref Sexp;
		for(el := setof(t1); el != nil; el = tl el){
			x := tagintersect(hd el, t2);
			if(x != nil)
				rl = x :: rl;
		}
		return mkset(rev(rl));	# null if empty

	(Abytes<<4) | Aprefix =>	# case (VII)
		if(isprefix(t2, t1))
			return t1;
	(Abytes<<4) | Arange =>	# case (VII)
		if(inrange(t1, t2))
			return t1;
	(Abytes<<4) | Asuffix =>	# case (VII)
		if(issuffix(t2, t1))
			return t1;
				
	(Aprefix<<4) | Aprefix =>	# case (VIII)
		p1 := prefixof(t1);
		p2 := prefixof(t2);
		if(p1 == nil || p2 == nil)
			return nil;
		if(p1.nb < p2.nb){
			(t1, t2) = (t2, t1);
			(p1, p2) = (p2, p1);
		}
		if((*p2).isprefix(*p1))
			return t1;	# t1 is longer, thus more specific
				
	(Asuffix<<4) | Asuffix =>	# case (VIII)	extension
		p1 := suffixof(t1);
		p2 := suffixof(t2);
		if(p1 == nil || p2 == nil)
			return nil;
		if(p1.nb < p2.nb){
			(t1, t2) = (t2, t1);
			(p1, p2) = (p2, p1);
		}
		if((*p2).issuffix(*p1))
			return t1;	# t1 is longer, thus more specific

	(Arange<<4) | Aprefix =>	# case (IX)
		return nil;
	(Arange<<4) | Asuffix =>	# case (IX)
		return nil;
	(Arange<<4) | Arange =>	# case (IX)
		v1 := rangeof(t1);
		v2 := rangeof(t2);
		if(v1 == nil || v2 == nil)
			return nil;	# invalid
		(ok, v) := (*v1).intersect(*v2);
		if(ok)
			return mkrange(v);

	(Alist<<4) | Arange or
	(Alist<<4) | Aprefix =>	# case (X)
		;
	}
	return nil;	# case (X), and default
}

isprefix(pat, subj: ref Sexp): int
{
	p := prefixof(pat);
	if(p == nil)
		return 0;
	return (*p).isprefix(valof(subj));
}

issuffix(pat, subj: ref Sexp): int
{
	p := suffixof(pat);
	if(p == nil)
		return 0;
	return (*p).issuffix(valof(subj));
}

inrange(t1, t2: ref Sexp): int
{
	v := valof(t1);
	r := rangeof(t2);
	if(r == nil)
		return 0;
	if(0)
		sys->print("%s :: %s\n", v.text(), (*r).text());
	pass := 0;
	if(r.ge >= 0){
		c := v.cmp(r.lb, r.order);
		if(c < 0 || c == 0 && !r.ge)
			return 0;
		pass = 1;
	}
	if(r.le >= 0){
		c := v.cmp(r.ub, r.order);
		if(c > 0 || c == 0 && !r.le)
			return 0;
		pass = 1;
	}
	return pass;
}

addval(l: list of ref Sexp, s: string, v: Val): list of ref Sexp
{
	e: ref Sexp;
	if(v.a != nil)
		e = ref Sexp.Binary(v.a, v.hint);
	else
		e = ref Sexp.String(v.s, v.hint);
	return ref Sexp.String(s, nil) :: e :: l;
}

mkrange(r: Vrange): ref Sexp
{
	l: list of ref Sexp;
	if(r.le > 0)
		l = addval(l, "le", r.ub);
	else if(r.le == 0)
		l = addval(l, "l", r.ub);
	if(r.ge > 0)
		l = addval(l, "ge", r.lb);
	else if(r.ge == 0)
		l = addval(l, "g", r.lb);
	return ref Sexp.List(ref Sexp.String("*",nil) :: ref Sexp.String("range",nil) :: ref Sexp.String(r.otext(), nil) :: l);
}

valof(s: ref Sexp): Val
{
	pick r := s {
	String =>
		return Val.mk(r.s, nil, r.hint);
	Binary =>
		return Val.mk(nil, r.data, r.hint);
	* =>
		return Val.mk(nil, nil, nil);	# can't happen
	}
}

starop(s: ref Sexp, op: string): (string, list of ref Sexp)
{
	if(s == nil)
		return (nil, nil);
	pick r := s {
	List =>
		if(r.op() == "*" && tl r.l != nil){
			pick t := hd tl r.l {
			String =>
				if(op != nil && t.s != op)
					return (nil, nil);
				return (t.s, tl tl r.l);
			}
		}
	}
	return (nil, nil);
}

isset(s: ref Sexp): (int, list of ref Sexp)
{
	(op, l) := starop(s, "set");
	if(op != nil)
		return (1, l);
	return (0, l);
}

setof(s: ref Sexp): list of ref Sexp
{
	return starop(s, "set").t1;
}

prefixof(s: ref Sexp): ref Val
{
	return substrof(s, "prefix");
}

suffixof(s: ref Sexp): ref Val
{
	return substrof(s, "suffix");
}

substrof(s: ref Sexp, kind: string): ref Val
{
	l := starop(s, kind).t1;
	if(l == nil)
		return nil;
	pick x := hd l{
	String =>
		return ref Val.mk(x.s, nil, x.hint);
	Binary =>
		return ref Val.mk(nil, x.data, x.hint);
	}
	return nil;
}

rangeof(s: ref Sexp): ref Vrange
{
	l := starop(s, "range").t1;
	if(l == nil)
		return nil;
	ord: int;
	case (hd l).astext() {
	"alpha" =>	ord = Alpha;
	"numeric" =>	ord = Numeric;
	"binary" =>	ord = Binary;
	"time" =>	ord = Time;	# hh:mm:ss
	"date" =>	ord = Date;	# full date format
	* =>	return nil;
	}
	l = tl l;
	lb, ub: Val;
	lt := -1;
	gt := -1;
	while(l != nil){
		if(tl l == nil)
			return nil;
		o := (hd l).astext();
		v: Val;
		l = tl l;
		if(l == nil)
			return nil;
		pick t := hd l {
		String =>
			v = Val.mk(t.s, nil, t.hint);
		Binary =>
			v = Val.mk(nil, t.data, t.hint);
		* =>
			return nil;
		}
		l = tl l;
		case o {
		"g" or "ge" =>
			if(gt >= 0 || lt >= 0)
				return nil;
			gt = o == "ge";
			lb = v;
		"l" or "le" =>
			if(lt >= 0)
				return nil;
			lt = o == "le";
			ub = v;
		* =>
			return nil;
		}
	}
	if(gt < 0 && lt < 0)
		return nil;
	return ref Vrange(ord, gt, lb, lt, ub);
}

Els: adt {
	a:	array of ref Sexp;
	n:	int;

	add:	fn(el: self ref Els, s: ref Sexp);
	els:	fn(el: self ref Els): array of ref Sexp;
};

Els.add(el: self ref Els, s: ref Sexp)
{
	if(el.n >= len el.a){
		t := array[el.n+10] of ref Sexp;
		if(el.a != nil)
			t[0:] = el.a;
		el.a = t;
	}
	el.a[el.n++] = s;
}

Els.els(el: self ref Els): array of ref Sexp
{
	if(el.n == 0)
		return nil;
	return el.a[0:el.n];
}

remake(s: ref Sexp): ref Sexp
{
	if(s == nil)
		return nil;
	pick r := s {
	List =>
		(is, mem) := isset(r);
		if(is){
			el := ref Els(array[10] of ref Sexp, 0);
			members(mem, el);
			if(debug)
				sys->print("-- %#q\n", s.text());
			y := mkset0(tolist(el.els()));
			if(debug){
				if(y == nil)
					sys->print("\t=> EMPTY\n");
				else
					sys->print("\t=> %#q\n", y.text());
			}
			return y;
		}
		rl: list of ref Sexp;
		for(l := r.l; l != nil; l = tl l){
			e := remake(hd l);
			if(e != hd l){
				# structure changed, remake current node's list
				for(il := r.l; il != l; il = tl il)
					rl = hd il :: rl;
				rl = e :: rl;
				while((l = tl l) != nil)
					rl = remake(hd l) :: rl;
				return ref Sexp.List(rev(rl));
			}
		}
		# unchanged
	}
	return s;
}

members(l: list of ref Sexp, el: ref Els)
{
	for(; l != nil; l = tl l){
		e := hd l;
		(is, mem) := isset(e);
		if(is)
			members(mem, el);
		else
			el.add(remake(e));
	}
}

mkset(sl: list of ref Sexp): ref Sexp
{
	rl: list of ref Sexp;
	for(l := sl; l != nil; l = tl l){
		(is, mem) := isset(hd l);
		if(is){
			for(; mem != nil; mem = tl mem)
				rl = hd mem :: rl;
		}else
			rl = hd l :: rl;
	}
	return mkset0(rev(rl));
}

mkset0(mem: list of ref Sexp): ref Sexp
{
	if(mem == nil)
		return nil;
	return ref Sexp.List(ref Sexp.String("*", nil) :: ref Sexp.String("set", nil) :: mem);
}

factor(a: array of ref Sexp): ref Sexp
{
	mergesort(a, array[len a] of ref Sexp);
	for(i := 0; i < len a; i++){
		case tagindex(a[i]) {
		Astar =>
			return a[i];
		Alist =>
			k := i+1;
			if(k >= len a)
				break;
			if(a[k].islist() && (op := a[i].op()) != "*" && op == a[k].op()){
				# ensure tag uniqueness within a set by: (* set (a L1) (a L2)) => (a (* set L1 L2))
				ml := a[i].els();
				n0 := hd ml;
				rl := ref Sexp.List(tl ml) :: ref Sexp.String("set", nil) :: ref Sexp.String("*", nil) :: nil;	# reversed
				# gather tails of adjacent lists with op matching this one
				for(; k < len a && a[k].islist() && a[k].op() == op; k++){
					ml = tl a[k].els();
					if(len ml == 1)
						rl = hd ml :: rl;
					else
						rl = ref Sexp.List(ml) :: rl;
				}
				a[i] = ref Sexp.List(n0 :: remake(ref Sexp.List(rev(rl))) :: nil);
				sys->print("common: %q [%d -> %d] -> %q\n", op, i, k-1, a[i].text());
				if(k < len a)
					a[i+1:] = a[k:];
				a = a[0:i+1+(len a-k)];
			}
		}
	}
	return mkset0(tolist(a));
}

tolist(a: array of ref Sexp): list of ref Sexp
{
	l: list of ref Sexp;
	for(i := len a; --i >= 0;)
		l = a[i] :: l;
	return l;
}

mergesort(a, b: array of ref Sexp)
{
	r := len a;
	if(r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m]);
		mergesort(a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if(b[i].islist() || !b[j].islist() && b[i].op() > b[j].op())	# a list is greater than any atom
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if(i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}

Val: adt {
	# only one of s or a is not nil
	s:	string;
	a:	array of byte;
	hint:	string;
	nb:	int;	# size in bytes

	mk:	fn(s: string, a: array of byte, h: string): Val;
	cmp:	fn(a: self Val, b: Val, order: int): int;
	isfloat:	fn(a: self Val): int;
	isprefix:	fn(a: self Val, b: Val): int;
	issuffix:	fn(a: self Val, b: Val): int;
	bytes:	fn(a: self Val): array of byte;
	text:	fn(v: self Val): string;
};

Val.mk(s: string, a: array of byte, h: string): Val
{
	if(a != nil)
		nb := len a;
	else
		nb = utflen(s);
	return Val(s, a, h, nb);
}

Val.bytes(v: self Val): array of byte
{
	if(v.a != nil)
		return v.a;
	return array of byte v.s;
}

Val.isfloat(v: self Val): int
{
	if(v.a != nil)
		return 0;
	for(i := 0; i < len v.s; i++)
		if(v.s[i] == '.')
			return 1;
	return 0;
}

Val.isprefix(a: self Val, b: Val): int
{
	if(a.hint != b.hint)
		return 0;
	# normalise to bytes
	va := a.bytes();
	vb := b.bytes();
	for(i := 0; i < len va; i++)
		if(i >= len vb || va[i] != vb[i])
			return 0;
	return 1;
}

Val.issuffix(a: self Val, b: Val): int
{
	if(a.hint != b.hint)
		return 0;
	# normalise to bytes
	va := a.bytes();
	vb := b.bytes();
	for(i := 0; i < len va; i++)
		if(i >= len vb || va[len va-i-1] != vb[len vb-i-1])
			return 0;
	return 1;
}

Val.cmp(a: self Val, b: Val, order: int): int
{
	if(a.hint != b.hint)
		return -2;
	case order {
	Numeric =>	# TO DO: change this to use string comparisons
		if(a.a != nil || b.a != nil)
			return -2;
		if(a.isfloat() || b.isfloat()){
			fa := real a.s;
			fb := real b.s;
			if(fa < fb)
				return -1;
			if(fa > fb)
				return 1;
			return 0;
		}
		ia := big a.s;
		ib := big b.s;
		if(ia < ib)
			return -1;
		if(ia > ib)
			return 1;
		return 0;
	Binary =>	# right-justified, unsigned binary values
		av := a.a;
		if(av == nil)
			av = array of byte a.s;
		bv := b.a;
		if(bv == nil)
			bv = array of byte b.s;
		while(len av > len bv){
			if(av[0] != byte 0)
				return 1;
			av = av[1:];
		}
		while(len bv > len av){
			if(bv[0] != byte 0)
				return -1;
			bv = bv[1:];
		}
		return cmpbytes(av, bv);
	}
	# otherwise compare as strings
	if(a.a != nil){
		if(b.s != nil)
			return cmpbytes(a.a, array of byte b.s);
		return cmpbytes(a.a, b.a);
	}
	if(b.a != nil)
		return cmpbytes(array of byte a.s, b.a);
	if(a.s < b.s)
		return -1;
	if(a.s > b.s)
		return 1;
	return 0;
}

Val.text(v: self Val): string
{
	s: string;
	if(v.hint != nil)
		s = sys->sprint("[%s]", v.hint);
	if(v.s != nil)
		return s+v.s;
	if(v.a != nil)
		return sys->sprint("%s#%s#", s, base16->enc(v.a));
	return sys->sprint("%s\"\"", s);
}

cmpbytes(a, b: array of byte): int
{
	n := len a;
	if(n > len b)
		n = len b;
	for(i := 0; i < n; i++)
		if(a[i] != b[i])
			return int a[i] - int b[i];
	return len a - len b;
}

Vrange: adt {
	order:	int;
	ge:	int;
	lb:	Val;
	le:	int;
	ub:	Val;

	text:	fn(v: self Vrange): string;
	otext:	fn(v: self Vrange): string;
	intersect:	fn(a: self Vrange, b: Vrange): (int, Vrange);
};

Alpha, Numeric, Time, Binary, Date: con iota;	# Vrange.order

Vrange.otext(r: self Vrange): string
{
	case r.order {
	Alpha =>	return "alpha";
	Numeric =>	return "numeric";
	Time =>	return "time";
	Binary =>	return "binary";
	Date => return "date";
	* => return sys->sprint("O%d", r.order);
	}
}

Vrange.text(v: self Vrange): string
{
	s := sys->sprint("(* range %s", v.otext());
	if(v.ge >= 0){
		s += " g";
		if(v.ge)
			s += "e";
		s += " "+v.lb.text();
	}
	if(v.le >= 0){
		s += " l";
		if(v.le)
			s += "e";
		s += " "+v.ub.text();
	}
	return s+")";
}

Vrange.intersect(v1: self Vrange, v2: Vrange): (int, Vrange)
{
	if(v1.order != v2.order)
		return (0, v1);	# incommensurate
	v := v1;
	if(v.ge < 0 || v2.ge >= 0 && v2.lb.cmp(v.lb, v.order) > 0)
		v.lb = v2.lb;
	if(v.le < 0 || v2.le >= 0 && v2.ub.cmp(v.ub, v.order) < 0)
		v.ub = v2.ub;
	if(v.lb.hint != v.ub.hint)
		return (0, v1);	# incommensurate
	v.ge &= v2.ge;
	v.le &= v2.le;
	c := v.lb.cmp(v.ub, v.order);
	if(c > 0 || c == 0 && !(v.ge && v.le))
		return (0, v1);	# empty range
	return (1, v);
}

utflen(s: string): int
{
	return len array of byte s;
}

append[T](l1, l2: list of T): list of T
{
	rl1: list of T;
	for(; l1 != nil; l1 = tl l1)
		rl1 = hd l1 :: rl1;
	for(; rl1 != nil; rl1 = tl rl1)
		l2 = hd rl1 :: l2;
	return l2;
}

rev[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

revt[S,T](l: list of (S,T)): list of (S,T)
{
	rl: list of (S,T);
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

#
# the following should probably be in a separate Limbo library module,
# or provided in some way directly by Keyring
#

Keyrep: adt {
	alg:	string;
	owner:	string;
	els:	list of (string, ref IPint);
	pick{	# keeps a type distance between public and private keys
	PK =>
	SK =>
	}

	pk:	fn(pk: ref Keyring->PK): ref Keyrep.PK;
	sk:	fn(sk: ref Keyring->SK): ref Keyrep.SK;
	mkpk:	fn(k: self ref Keyrep): (ref Keyring->PK, int);
	mksk:	fn(k: self ref Keyrep): ref Keyring->SK;
	get:	fn(k: self ref Keyrep, n: string): ref IPint;
	getb:	fn(k: self ref Keyrep, n: string): array of byte;
	eq:	fn(k1: self ref Keyrep, k2: ref Keyrep): int;
};

#
# convert an Inferno key into a (name, IPint) representation,
# where `names' maps between Inferno key component offsets and factotum names
#
keyextract(flds: list of string, names: list of (string, int)): list of (string, ref IPint)
{
	a := array[len flds] of ref IPint;
	for(i := 0; i < len a; i++){
		a[i] = IPint.b64toip(hd flds);
		flds = tl flds;
	}
	rl: list of (string, ref IPint);
	for(; names != nil; names = tl names){
		(n, p) := hd names;
		if(p < len a)
			rl = (n, a[p]) :: rl;
	}
	return revt(rl);
}

Keyrep.pk(pk: ref Keyring->PK): ref Keyrep.PK
{
	s := kr->pktostr(pk);
	(nf, flds) := sys->tokenize(s, "\n");
	if((nf -= 2) < 0)
		return nil;
	case hd flds {
	"rsa" =>
		return ref Keyrep.PK(hd flds, hd tl flds,
			keyextract(tl tl flds, list of {("ek",1), ("n",0)}));
	"elgamal" =>
		return ref Keyrep.PK(hd flds, hd tl flds,
			keyextract(tl tl flds, list of {("p",0), ("alpha",1), ("key",2)}));
	"dsa" =>
		return ref Keyrep.PK(hd flds, hd tl flds,
			keyextract(tl tl flds, list of {("p",0), ("alpha",2), ("q",1), ("key",3)}));
	* =>
		return nil;
	}
}

Keyrep.sk(pk: ref Keyring->SK): ref Keyrep.SK
{
	s := kr->sktostr(pk);
	(nf, flds) := sys->tokenize(s, "\n");
	if((nf -= 2) < 0)
		return nil;
	# the ordering of components below should match the one defined in the spki spec
	case hd flds {
	"rsa" =>
		return ref Keyrep.SK(hd flds, hd tl flds,
			keyextract(tl tl flds,list of {("ek",1), ("n",0), ("!dk",2), ("!q",4), ("!p",3), ("!kq",6), ("!kp",5), ("!c2",7)}));	# see comment elsewhere about p, q
	"elgamal" =>
		return ref Keyrep.SK(hd flds, hd tl flds,
			keyextract(tl tl flds, list of {("p",0), ("alpha",1), ("key",2), ("!secret",3)}));
	"dsa" =>
		return ref Keyrep.SK(hd flds, hd tl flds,
			keyextract(tl tl flds, list of {("p",0), ("alpha",2), ("q",1), ("key",3), ("!secret",4)}));
	* =>
		return nil;
	}
}

Keyrep.get(k: self ref Keyrep, n: string): ref IPint
{
	n1 := f2s("rsa", n);
	for(el := k.els; el != nil; el = tl el)
		if((hd el).t0 == n || (hd el).t0 == n1)
			return (hd el).t1;
	return nil;
}

Keyrep.getb(k: self ref Keyrep, n: string): array of byte
{
	v := k.get(n);
	if(v == nil)
		return nil;
	return pre0(v.iptobebytes());
}

Keyrep.mkpk(k: self ref Keyrep): (ref Keyring->PK, int)
{
	case k.alg {
	"rsa" =>
		e := k.get("ek");
		n := k.get("n");
		if(e == nil || n == nil)
			return (nil, 0);
		return (kr->strtopk(sys->sprint("rsa\n%s\n%s\n%s\n", k.owner, n.iptob64(), e.iptob64())), n.bits());
	* =>
		raise "Keyrep: unknown algorithm";
	}
}

Keyrep.mksk(k: self ref Keyrep): ref Keyring->SK
{
	case k.alg {
	"rsa" =>
		e := k.get("ek");
		n := k.get("n");
		dk := k.get("!dk");
		p := k.get("!p");
		q := k.get("!q");
		kp := k.get("!kp");
		kq := k.get("!kq");
		c12 := k.get("!c2");
		if(e == nil || n == nil || dk == nil || p == nil || q == nil || kp == nil || kq == nil || c12 == nil)
			return nil;
		return kr->strtosk(sys->sprint("rsa\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
			k.owner, n.iptob64(), e.iptob64(), dk.iptob64(), p.iptob64(), q.iptob64(),
			kp.iptob64(), kq.iptob64(), c12.iptob64()));
	* =>
		raise "Keyrep: unknown algorithm";
	}
}

#
# account for naming differences between keyring and factotum, and spki.
# this might not be the best place for this.
#
s2f(s: string): string
{
	case s {
	"e" => return "ek";
	"d" => return "!dk";
	"p" => return "!q";		# NB: p and q (kp and kq) roles are reversed between libsec and pkcs
	"q" => return "!p";
	"a" => return "!kq";
	"b" => return "!kp";
	"c" => return "!c2";
	* =>	return s;
	}
}

f2s(alg: string, s: string): string
{
	case alg {
	"rsa" =>
		case s {
		"ek" =>	return "e";
		"!p" =>	return "q";	# see above
		"!q" =>	return "p";
		"!dk" =>	return "d";
		"!kp" =>	return "b";
		"!kq" =>	return "a";
		"!c2" =>	return "c";
		}
	"dsa" =>
		case s {
		"p" or "q" =>	return s;
		"alpha" =>	return "g";
		"key" =>	return "y";
		}
	* =>
		;
	}
	if(s != nil && s[0] == '!')
		return s[1:];
	return s;
}

Keyrep.eq(k1: self ref Keyrep, k2: ref Keyrep): int
{
	# n⁲ but n is small
	for(l1 := k1.els; l1 != nil; l1 = tl l1){
		(n, v1) := hd l1;
		v2 := k2.get(n);
		if(v2 == nil || !v1.eq(v2))
			return 0;
	}
	for(l2 := k2.els; l2 != nil; l2 = tl l2)
		if(k1.get((hd l2).t0) == nil)
			return 0;
	return 1;
}

sig2icert(sig: ref Signature, signer: string, exp: int): ref Keyring->Certificate
{
	if(sig.sig == nil)
		return nil;
	s := sys->sprint("%s\n%s\n%s\n%d\n%s\n", "rsa", sig.hash.alg, signer, exp, base64->enc((hd sig.sig).t1));
#sys->print("alg %s *** %s\n", sig.sa, base64->enc((hd sig.sig).t1));
	return kr->strtocert(s);
}

icert2els(cert: ref Keyring->Certificate): (string, string, string, list of (string, array of byte))
{
	s := kr->certtoattr(cert);
	if(s == nil)
		return (nil, nil, nil, nil);
	(nil, l) := sys->tokenize(s, " ");	# really need parseattr, and a better interface
	vals: list of (string, array of byte);
	alg, hashalg, signer: string;
	for(; l != nil; l = tl l){
		(nf, fld) := sys->tokenize(hd l, "=");
		if(nf != 2)
			continue;
		case hd fld {
		"sigalg" =>
			(nf, fld) = sys->tokenize(hd tl fld, "-");
			if(nf != 2)
				continue;
			alg = hd fld;
			hashalg = hd tl fld;
		"signer" =>
			signer = hd tl fld;
		"expires" =>
			;	# don't care
		* =>
			vals = (hd fld, base16->dec(hd tl fld)) :: vals;
		}
	}
	return (alg, hashalg, signer, revt(vals));
}

#
# pkcs1 asn.1 DER encodings
#

pkcs1_md5_pfx := array[] of {
	byte 16r30, byte 32,                 # SEQUENCE in 32 bytes
		byte 16r30, byte 12,                 # SEQUENCE in 12 bytes
			byte 6, byte 8,                     # OBJECT IDENTIFIER in 8 bytes
				byte (40*1+2),                   # iso(1) member-body(2)
				byte (16r80 + 6), byte 72,             # US(840)
				byte (16r80 + 6), byte (16r80 + 119), byte 13, # rsadsi(113549)
				byte 2,                        # digestAlgorithm(2)
				byte 5,                        # md5(5), end of OBJECT IDENTIFIER
			byte 16r05, byte 0,                  # NULL parameter, end of SEQUENCE
		byte 16r04, byte 16             #OCTET STRING in 16 bytes (MD5 length)
} ; 

pkcs1_sha1_pfx := array[] of {
	byte 16r30, byte 33,               # SEQUENCE in 33 bytes
		byte 16r30, byte 9,                 # SEQUENCE in 9 bytes
			byte 6, byte 5,                    # OBJECT IDENTIFIER in 5 bytes
				byte (40*1+3),                  # iso(1) member-body(3)
				byte 14,                      # ??(14)
				byte 3,                       # ??(3)
				byte 2,                       # digestAlgorithm(2)
				byte 26,                     # sha1(26), end of OBJECT IDENTIFIER
			byte 16r05, byte 0,          # NULL parameter, end of SEQUENCE
		byte 16r40, byte 20	# OCTET STRING in 20 bytes (SHA1 length)
};

#
# mlen should be key length in bytes
#
pkcs1_encode(ha: string, hash: array of byte, mlen: int): array of byte
{
	# apply hash function to message
	prefix: array of byte;
	case ha {
	"md5" =>
		prefix = pkcs1_md5_pfx;
	"sha" or "sha1" =>
		prefix = pkcs1_sha1_pfx;
	* =>
		return nil;
	}
	tlen := len prefix + len hash;
	if(mlen < tlen + 11)
		return nil;	# "intended encoded message length too short"
	pslen := mlen - tlen - 3;
	out := array[mlen] of byte;
	out[0] = byte 0;
	out[1] = byte 1;
	for(i:=0; i<pslen; i++)
		out[i+2] = byte 16rFF;
	out[2+pslen] = byte 0;
	out[2+pslen+1:] = prefix;
	out[2+pslen+1+len prefix:] = hash;
	return out;
}

#
# for debugging
#
rsacomp(block: array of byte, akey: ref Key): array of byte
{
	key := Keyrep.pk(akey.pk);
	x := kr->IPint.bebytestoip(block);
	y := x.expmod(key.get("e"), key.get("n"));
	ybytes := y.iptobebytes();
#dump("rsacomp", ybytes);
	k := 1024; # key.modlen;
	ylen := len ybytes;
	if(ylen < k) {
		a := array[k] of { * =>  byte 0};
		a[k-ylen:] = ybytes[0:];
		ybytes = a;
	}
	else if(ylen > k) {
		# assume it has leading zeros (mod should make it so)
		a := array[k] of byte;
		a[0:] = ybytes[ylen-k:];
		ybytes = a;
	}
	return ybytes;
}
