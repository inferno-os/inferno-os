implement Crypttest;

# Known-answer tests for Crypt's modern primitives, run inside Inferno.
# ML-KEM-768 vectors (ACVP) are read from mlkem.vec, lines
# "keygen d z ek" and "encap ek m c k" in hex. ML-DSA-65 vectors (ACVP)
# are read from mldsa.vec, lines "keygen id seed pk" and
# "sigver id pk msg ctx sig pass" ("-" for an empty field).
# usage: crypttest [mlkem.vec [mldsa.vec]]

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "ipints.m";
include "crypt.m";
include "cpace.m";
	crypt: Crypt;

Crypttest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

ok := 0;
bad := 0;

unhex(s: string): array of byte
{
	a := array[len s/2] of byte;
	for(i := 0; i < len a; i++)
		a[i] = byte ((hexv(s[2*i])<<4) | hexv(s[2*i+1]));
	return a;
}

hexv(c: int): int
{
	if(c >= '0' && c <= '9')
		return c-'0';
	if(c >= 'a' && c <= 'f')
		return c-'a'+10;
	return c-'A'+10;
}

eq(a, b: array of byte): int
{
	if(a == nil || b == nil || len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

check(name: string, got, want: array of byte)
{
	if(eq(got, want))
		ok++;
	else{
		bad++;
		sys->print("FAIL %s\n", name);
	}
}

sha(a: array of byte): array of byte
{
	d := array[32] of byte;
	if(a == nil)
		return nil;
	crypt->sha256(a, len a, d, nil);
	return d;
}

# CPace over X25519 with SHA-512: draft-irtf-cfrg-cpace-15, appendix B.1
cpacetest()
{
	cpace := load Cpace Cpace->PATH;
	if(cpace == nil || cpace->init() != nil){
		bad++;
		sys->print("FAIL cannot load Cpace: %r\n");
		return;
	}
	sid := unhex("7e4b4791d6a8ef019b936c79fb7f2c57");
	ci := unhex("6f630b425f726573706f6e6465720b415f696e69746961746f72");
	g := cpace->generator(array of byte "Password", ci, sid);
	check("cpace generator", g, unhex("64e8099e3ea682cfdc5cb665c057ebb514d06bf23ebc9f743b51b82242327074"));
	ya := unhex("21b4f4bd9e64ed355c3eb676a28ebedaf6d8f17bdc365995b319097153044080");
	yb := unhex("848b0779ff415f0af4ea14df9dd1d3c29ac41d836c7808896c4eba19c51ac40a");
	pa := cpace->share(g, ya);
	pb := cpace->share(g, yb);
	check("cpace Ya", pa, unhex("1b02dad6dbd29a07b6d28c9e04cb2f184f0734350e32bb7e62ff9dbcfdb63d15"));
	check("cpace Yb", pb, unhex("20cda5955f82c4931545bcbf40758ce1010d7db4db2a907013d79c7a8fcf957f"));
	want := unhex("a051ee5ee2499d16da3f69f430218b8ea94a18a45b67f9e86495b382c33d14a5"+
		"c38cecc0cc834f960e39e0d1bf7d76b9ef5d54eecc5e0f386c97ad12da8c3d5f");
	ada := array of byte "ADa";
	adb := array of byte "ADb";
	check("cpace ISK, initiator", cpace->isk(sid, ya, pb, pa, ada, pb, adb), want);
	check("cpace ISK, responder", cpace->isk(sid, yb, pa, pa, ada, pb, adb), want);
	# a share of small order must be refused (the draft's B.1.10: the neutral element and a point of order 8)
	if(cpace->isk(sid, ya, array[32] of {* => byte 0}, pa, ada, pb, adb) == nil) ok++; else { bad++; sys->print("FAIL cpace takes the zero share\n"); }
	if(cpace->isk(sid, ya, unhex("e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800"), pa, ada, pb, adb) == nil) ok++; else { bad++; sys->print("FAIL cpace takes a share of order 8\n"); }
	# the Elligator map must take every 255-bit element: one with bit 254 set, and its negation
	fe := unhex("92806dc608984dbf4e4aae478c6ec453ae979cc01ecc1a2a7cf49f5cee56551b");
	neg := unhex("5b7f9239f767b240b1b551b873913bac5168633fe133e5d5830b60a311a9aa64");	# p - fe
	check("x25519map of -r", crypt->x25519map(neg), crypt->x25519map(fe));
	hi := array[32] of byte;
	hi[0:] = fe;
	hi[31] |= byte 16r80;	# the top bit is ignored
	check("x25519map ignores bit 255", crypt->x25519map(hi), crypt->x25519map(fe));
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	crypt = load Crypt Crypt->PATH;
	if(crypt == nil){
		sys->print("cannot load Crypt: %r\n");
		raise "fail:load";
	}

	# X25519, RFC 7748 6.1
	a := unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
	b := unhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
	k := unhex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742");
	check("x25519 a", crypt->x25519(a, crypt->x25519base(b)), k);
	check("x25519 b", crypt->x25519(b, crypt->x25519base(a)), k);
	check("x25519base", crypt->x25519base(a), unhex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"));

	# Ed25519, RFC 8032 7.1 test 1 and test 2
	seed := unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60");
	pub := unhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
	sig := unhex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");
	check("ed25519 pub", crypt->ed25519pub(seed), pub);
	check("ed25519 sign", crypt->ed25519sign(seed, array[0] of byte), sig);
	if(crypt->ed25519verify(pub, array[0] of byte, sig) == 1) ok++; else { bad++; sys->print("FAIL ed25519 verify\n"); }
	if(crypt->ed25519verify(pub, array[1] of {byte 1}, sig) == 0) ok++; else { bad++; sys->print("FAIL ed25519 verify accepts a wrong message\n"); }
	seed2 := unhex("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb");
	check("ed25519 sign 2", crypt->ed25519sign(seed2, unhex("72")),
		unhex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"));

	# HKDF-SHA256, RFC 5869 A.1 and A.3 (no salt, no info)
	check("hkdf 1", crypt->hkdfsha256(unhex("000102030405060708090a0b0c"), unhex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), unhex("f0f1f2f3f4f5f6f7f8f9"), 42),
		unhex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"));
	check("hkdf 3", crypt->hkdfsha256(nil, unhex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), nil, 42),
		unhex("8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"));

	# XChaCha20-Poly1305, draft-irtf-cfrg-xchacha-03 A.3.1
	key := array[32] of byte;
	for(i := 0; i < 32; i++)
		key[i] = byte (16r80+i);
	nonce := array[24] of byte;
	for(i = 0; i < 24; i++)
		nonce[i] = byte (16r40+i);
	ad := unhex("50515253c0c1c2c3c4c5c6c7");
	pt := array of byte "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
	sealed := crypt->xchachapolyseal(key, nonce, ad, pt);
	if(sealed != nil && len sealed == len pt + 16){
		check("xchacha tag", sealed[len pt:], unhex("c0875924c1c7987947deafd8780acf49"));
		check("xchacha ct", sealed[0:4], unhex("bd6d179d"));
	}else{
		bad++;
		sys->print("FAIL xchacha seal\n");
	}
	check("xchacha open", crypt->xchachapolyopen(key, nonce, ad, sealed), pt);
	sealed[3] ^= byte 1;
	if(crypt->xchachapolyopen(key, nonce, ad, sealed) == nil) ok++; else { bad++; sys->print("FAIL xchacha opens a changed message\n"); }

	cpacetest();

	# ML-KEM-768: ACVP vectors, then a random round trip
	file := "/lib/crypttest/mlkem.vec";
	if(len args > 1)
		file = hd tl args;
	f := bufio->open(file, Bufio->OREAD);
	nvec := 0;
	if(f == nil)
		sys->print("no %s: skipping the ACVP vectors\n", file);
	else while((s := f.gets('\n')) != nil){
		(n, flds) := sys->tokenize(s, " \n");
		if(n == 4 && hd flds == "keygen"){
			d := hd tl flds; z := hd tl tl flds; ek := hd tl tl tl flds;
			(gek, nil) := crypt->mlkem768keygenderand(unhex(d + z));
			check("mlkem keygen", gek, unhex(ek));
			nvec++;
		}else if(n == 5 && hd flds == "encap"){
			ek := hd tl flds; m := hd tl tl flds; c := hd tl tl tl flds; kk := hd tl tl tl tl flds;
			(gct, gss) := crypt->mlkem768encapderand(unhex(ek), unhex(m));
			check("mlkem encap ct", gct, unhex(c));
			check("mlkem encap ss", gss, unhex(kk));
			nvec++;
		}
	}
	(ek, dk) := crypt->mlkem768keygen();
	(ct, ss) := crypt->mlkem768encap(ek);
	check("mlkem round trip", crypt->mlkem768decap(dk, ct), ss);
	(ek2, nil) := crypt->mlkem768keygen();
	if(!eq(ek, ek2)) ok++; else { bad++; sys->print("FAIL mlkem keygen is not random\n"); }
	if(len ek == Crypt->MLKEM768eklen && len dk == Crypt->MLKEM768dklen && len ct == Crypt->MLKEM768ctlen) ok++; else { bad++; sys->print("FAIL mlkem sizes\n"); }

	# ML-DSA-65: ACVP key generation and verification vectors
	file = "/lib/crypttest/mldsa.vec";
	if(len args > 2)
		file = hd tl tl args;
	f = bufio->open(file, Bufio->OREAD);
	if(f == nil)
		sys->print("no %s: skipping the ML-DSA ACVP vectors\n", file);
	else while((s = f.gets('\n')) != nil){
		(n, flds) := sys->tokenize(s, " \n");
		if(n == 4 && hd flds == "keygen"){
			check("mldsa keygen "+hd tl flds, crypt->mldsa65pub(unhex(hd tl tl flds)), unhex(hd tl tl tl flds));
			nvec++;
		}else if(n == 7 && hd flds == "sigver"){
			a := array[6] of string;
			l := tl flds;
			for(j := 0; j < 6; j++){
				a[j] = hd l;
				if(a[j] == "-")
					a[j] = "";
				l = tl l;
			}
			if(crypt->mldsa65verify(unhex(a[1]), unhex(a[2]), unhex(a[3]), unhex(a[4])) == int a[5])
				ok++;
			else{
				bad++;
				sys->print("FAIL mldsa sigver %s\n", a[0]);
			}
			nvec++;
		}
	}
	# seed 00..1f (the IETF LAMPS example key) and its deterministic signature
	# of "pghybrid1" 0 "purgatorio" with no context, as dilithium-py and the
	# Rust rebuild (purg-auth, sig.rs) give them
	xi := array[32] of byte;
	for(i = 0; i < 32; i++)
		xi[i] = byte i;
	t0 := sys->millisec();
	mpk := crypt->mldsa65pub(xi);
	t1 := sys->millisec();
	mm := array[20] of {* => byte 0};
	mm[0:] = array of byte "pghybrid1";
	mm[10:] = array of byte "purgatorio";
	msig := crypt->mldsa65sign(xi, mm, nil);
	t2 := sys->millisec();
	check("mldsa pub", sha(mpk), unhex("d666806e11cee19a7c989f7445f90dd419cf4d2d51db8c0fdb4c0f0a542238c9"));
	check("mldsa sign", sha(msig), unhex("36b0d949a020bb5ecf9d9a2047b49b2da8da82ea7bb57621d7eec8d5ff85d75f"));
	t3 := sys->millisec();
	if(crypt->mldsa65verify(mpk, mm, nil, msig) == 1) ok++; else { bad++; sys->print("FAIL mldsa verify\n"); }
	t4 := sys->millisec();
	if(crypt->mldsa65verify(mpk, mm[0:19], nil, msig) == 0) ok++; else { bad++; sys->print("FAIL mldsa verify accepts a wrong message\n"); }
	if(crypt->mldsa65verify(mpk, mm, array of byte "x", msig) == 0) ok++; else { bad++; sys->print("FAIL mldsa verify accepts a wrong context\n"); }
	if(msig != nil){
		msig[100] ^= byte 1;
		if(crypt->mldsa65verify(mpk, mm, nil, msig) == 0) ok++; else { bad++; sys->print("FAIL mldsa verify accepts a changed signature\n"); }
	}else
		bad++;
	cx := array[255] of {* => byte 16rA5};
	csig := crypt->mldsa65sign(xi, mm, cx);
	if(csig != nil && crypt->mldsa65verify(mpk, mm, cx, csig) == 1 && crypt->mldsa65verify(mpk, mm, cx[0:254], csig) == 0) ok++; else { bad++; sys->print("FAIL mldsa context\n"); }
	if(crypt->mldsa65sign(xi, mm, array[256] of {* => byte 0}) == nil && crypt->mldsa65sign(xi[0:31], mm, nil) == nil
	&& crypt->mldsa65pub(xi[0:31]) == nil && crypt->mldsa65verify(mpk[0:1951], mm, nil, csig) == 0) ok++; else { bad++; sys->print("FAIL mldsa bad arguments\n"); }
	# time 20 of each
	t5 := sys->millisec();
	for(i = 0; i < 20; i++)
		crypt->mldsa65pub(xi);
	t6 := sys->millisec();
	for(i = 0; i < 20; i++){
		mm[19] = byte i;
		msig = crypt->mldsa65sign(xi, mm, nil);
	}
	t7 := sys->millisec();
	for(i = 0; i < 20; i++)
		crypt->mldsa65verify(mpk, mm, nil, msig);
	t8 := sys->millisec();
	sys->print("mldsa65 ms: first pub %d sign %d verify %d; mean of 20: pub %d.%.2d sign %d.%.2d verify %d.%.2d\n",
		t1-t0, t2-t1, t4-t3, (t6-t5)/20, (t6-t5)*5%100, (t7-t6)/20, (t7-t6)*5%100, (t8-t7)/20, (t8-t7)*5%100);

	sys->print("crypttest: %d ok, %d failed (%d ACVP vectors)\n", ok, bad, nvec);
	if(bad)
		raise "fail:crypttest";
}
