implement Verifier;

#
# Copyright © 2004 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;

include "ipints.m";
include "crypt.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "sexprs.m";
	sexprs: Sexprs;
	Sexp: import sexprs;

include "spki.m";
	spki: SPKI;
	Hash, Key, Cert, Name, Subject, Signature, Seqel, Toplev, Valid: import spki;
	dump: import spki;

include "encoding.m";
	base64: Encoding;

debug := 0;

init()
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	sexprs = load Sexprs Sexprs->PATH;
	spki = load SPKI SPKI->PATH;
	base64 = load Encoding Encoding->BASE64PATH;

	sexprs->init();
	spki->init();
}

putkey(keys: list of ref Key, k: ref Key): list of ref Key
{
	for(kl := keys; kl != nil; kl = tl kl)
		if(k.eq(hd kl))
			return keys;
	return k :: keys;
}

keybyhash(hl: list of ref Hash, keys: list of ref Key): ref Key
{
	for(kl := keys; kl != nil; kl = tl kl){
		k := hd kl;
		if(k.hash != nil && anyhashmatch(hl, k.hash))
			return k;
	}
	return nil;
}

anyhashmatch(hl1, hl2: list of ref Hash): int
{
	for(; hl1 != nil; hl1 = tl hl1){
		h1 := hd hl1;
		for(; hl2 != nil; hl2 = tl hl2)
			if(h1.eq(hd hl2))
				return 1;
	}
	return 0;
}

verify(seq: list of ref Seqel): (ref Speaksfor, list of ref Seqel, string)
{
	stack: list of ref Seqel;
	keys: list of ref Key;
	n0: ref Name;
	cn: ref Cert;
	delegate := 1;
	tag: ref Sexp;
	val: ref Valid;
	for(; seq != nil; seq = tl seq){
		pick s := hd seq {
		C =>
			diag := checkcert(s.c);
			if(diag != nil)
				return (nil, seq, diag);
			if(stack != nil){
				pick h := hd stack {
				C =>
					if(!delegate)
						return(nil, seq, "previous auth certificate did not delegate");
					if(!h.c.subject.principal().eq(s.c.issuer.principal))
						return (nil, seq, "certificate chain has mismatched principals");
					if(debug)
						sys->print("issuer %s ok\n", s.c.issuer.principal.text());
				}
				stack = tl stack;
			}
			stack = s :: stack;
			if(n0 == nil)
				n0 = s.c.issuer;
			cn = s.c;
			pick t := s.c {
			A or KH or O =>
				delegate = t.delegate;
				if(tag != nil){
					tag = spki->tagintersect(tag, t.tag);
					if(tag == nil)
						return (nil, seq, "certificate chain has null authority");
				}else
					tag = t.tag;
				if(val != nil){
					if(t.valid != nil){
						(ok, iv) := (*val).intersect(*t.valid);
						if(!ok)
							return (nil, seq, "certificate chain is not currently valid");
						*val = iv;
					}
				}else
					val = t.valid;
			}
		K =>
			stack = s :: stack;
		O =>
			if(s.op == "debug"){
				debug = !debug;
				continue;
			}
			if(s.op != "hash" || s.args == nil || tl s.args != nil)
				return (nil, seq, "invalid operation to `do'");
			alg := (hd s.args).astext();
			if(alg != "md5" && alg != "sha1")
				return (nil, seq, "invalid hash operation");
			if(stack == nil)
				return (nil, seq, "verification stack empty");
			pick h := hd stack {
			K =>
				a := h.k.hashed(alg);
				if(debug)
					dump("do hash", a);
				keys = putkey(keys, h.k);
				stack = tl stack;
			C =>
				;
			* =>
				return (nil, seq, "invalid type of operand for hash");
			}
		S =>
			if(stack == nil)
				return (nil, seq, "verification stack empty");
			sig := s.sig;
			if(sig.key == nil)
				return (nil, seq, "neither hash nor key for signature");
			if(sig.key.pk == nil){
				k := keybyhash(sig.key.hash, keys);
				if(k == nil)
					return (nil, seq, "unknown key for signature");
				sig.key = k;
			}
			pick c := hd stack {
			C =>
				if(c.c.e == nil)
					return (nil, seq, "missing canonical expression for cert");
				a := c.c.e.pack();
				# verify signature ...
				if(debug)
					dump("cert a", a);
				h := spki->hashbytes(a, "md5");
				if(debug){
					dump("hash cert", h);
					sys->print("hash = %q\n", base64->enc(h));
				}
				failed := spki->checksig(c.c, sig);
				if(debug)
					sys->print("checksig: %q\n", failed);
				if(failed != nil)
					return (nil, seq, "signature verification failed: "+failed);
			* =>
				return (nil, seq, "invalid type of signature operand");
			}
		}
	}
	if(n0 != nil && cn != nil){
		if(debug){
			if(tag != nil)
				auth := sys->sprint(" regarding %q", tag.text());
			sys->print("%q speaks for %q%s\n", cn.subject.text(), n0.text(), auth);
		}
		return (ref Speaksfor(cn.subject, n0, tag, val), nil, nil);
	}
	return (nil, nil, nil);
}

checkcert(c: ref Cert): string
{
	# TO DO?
	return nil;
}
