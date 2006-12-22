implement Keyreps;
include "sys.m";
	sys: Sys;
include "keyring.m";
	kr: Keyring;
	IPint: import kr;
include "sexprs.m";
include "spki.m";
include "encoding.m";
	base64: Encoding;
include "keyreps.m";

init()
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	base64 = load Encoding Encoding->BASE64PATH;
}

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
			keyextract(tl tl flds, list of {("e",1), ("n",0)}));
	"elgamal" or "dsa" =>
		return ref Keyrep.PK(hd flds, hd tl flds,
			keyextract(tl tl flds, list of {("p",0), ("alpha",1), ("key",2)}));
	* =>
		return nil;
	}
}

Keyrep.sk(pk: ref Keyring->SK): ref Keyrep.SK
{
	s := kr->pktostr(pk);
	(nf, flds) := sys->tokenize(s, "\n");
	if((nf -= 2) < 0)
		return nil;
	case hd flds {
	"rsa" =>
		return ref Keyrep.SK(hd flds, hd tl flds,
			keyextract(tl tl flds,list of {("e",1), ("n",0), ("!dk",2), ("!p",3), ("!q",4), ("!kp",5), ("!kq",6), ("!c2",7)}));
	"elgamal" or "dsa" =>
		return ref Keyrep.SK(hd flds, hd tl flds,
			keyextract(tl tl flds, list of {("p",0), ("alpha",1), ("key",2), ("!secret",3)}));
	* =>
		return nil;
	}
}

Keyrep.get(k: self ref Keyrep, n: string): ref IPint
{
	for(el := k.els; el != nil; el = tl el)
		if((hd el).t0 == n)
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

Keyrep.mkpk(k: self ref Keyrep): (ref Keyring->PK, int)
{
	case k.alg {
	"rsa" =>
		e := k.get("e");
		n := k.get("n");
		return (kr->strtopk(sys->sprint("rsa\n%s\n%s\n%s\n", k.owner, n.iptob64(), e.iptob64())), n.bits());
	* =>
		raise "Keyrep: unknown algorithm" + k.alg;
	}
}

Keyrep.mksk(k: self ref Keyrep): ref Keyring->SK
{
	case k.alg {
	"rsa" =>
		e := k.get("e");
		n := k.get("n");
		dk := k.get("!dk");
		p := k.get("!p");
		q := k.get("!q");
		kp := k.get("!kp");
		kq := k.get("!kq");
		c12 := k.get("!c2");
		return kr->strtosk(sys->sprint("rsa\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
			k.owner, n.iptob64(), e.iptob64(), dk.iptob64(), p.iptob64(), q.iptob64(),
			kp.iptob64(), kq.iptob64(), c12.iptob64()));
	* =>
		raise "Keyrep: unknown algorithm";
	}
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

Keyrep.mkkey(kr: self ref Keyrep): ref SPKI->Key
{
	k := ref SPKI->Key;
	(k.pk, k.nbits) = kr.mkpk();
	k.sk = kr.mksk();
	return k;
}

sig2icert(sig: ref SPKI->Signature, signer: string, exp: int): ref Keyring->Certificate
{
	if(sig.sig == nil)
		return nil;
	s := sys->sprint("%s\n%s\n%s\n%d\n%s\n", "rsa", sig.hash.alg, signer, exp, base64->enc((hd sig.sig).t1));
#sys->print("alg %s *** %s\n", sig.sa, base64->enc((hd sig.sig).t1));
	return kr->strtocert(s);
}

revt[S,T](l: list of (S,T)): list of (S,T)
{
	rl: list of (S,T);
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}
