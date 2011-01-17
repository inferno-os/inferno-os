implement Verify;

#
# Copyright © 2004 Vita Nuova Holdings Limited
#

# work in progress

include "sys.m";
	sys: Sys;

include "draw.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

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

	verifier: Verifier;
	Speaksfor: import verifier;

include "encoding.m";
	base64: Encoding;

Verify: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

debug := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	bufio = load Bufio Bufio->PATH;
	sexprs = load Sexprs Sexprs->PATH;
	spki = load SPKI SPKI->PATH;
	verifier = load Verifier Verifier->PATH;
	base64 = load Encoding Encoding->BASE64PATH;

	sexprs->init();
	spki->init();
	verifier->init();

	f := bufio->fopen(sys->fildes(0), Sys->OREAD);
	for(;;){
		(e, err) := Sexp.read(f);
		if(e == nil && err == nil)
			break;
		if(err != nil)
			error(sys->sprint("invalid s-expression: %s", err));
		(top, diag) := spki->parse(e);
		if(diag != nil)
			error(sys->sprint("invalid SPKI structure: %s", diag));
		pick t := top {
		C =>
			if(debug)
				sys->print("cert: %s\n", t.v.text());
			a := spki->hashexp(e, "md5");
		Sig =>
			sys->print("got signature %q\n", t.v.text());
		K =>
			sys->print("got key %q\n", t.v.text());
		Seq =>
			els := t.v;
			if(debug){
				sys->print("(sequence");
				for(; els != nil; els = tl els)
					sys->print(" %s", (hd els).text());
				sys->print(")");
			}
			(claim, rem, whynot) := verifier->verify(t.v);
			if(whynot != nil){
				if(rem == nil)
					s := "end of sequence";
				else
					s = (hd rem).text();
				sys->fprint(sys->fildes(2), "verify: failed to verify at %#q: %s\n", s, whynot);
			}else{
				if(claim.regarding != nil)
					scope := sys->sprint(" regarding %q", claim.regarding.text());
				sys->print("verified: %q speaks for %q%s\n", claim.subject.text(), claim.name.text(), scope);
			}
		* =>
			sys->print("unexpected SPKI type: %q\n", e.text());
		}
	}
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "verify: %s\n", s);
	raise "fail:error";
}
