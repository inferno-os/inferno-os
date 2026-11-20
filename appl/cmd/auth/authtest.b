implement Authtest;

#
# authtest: Auth->client against Auth->server over a pipe, with keys made
# on the spot, for each kind of signer key. Prints one line for each case
# and a count; needs no network and no key files, so it runs anywhere,
# including a native kernel with nothing but a root file system.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
	kr: Keyring;
include "security.m";

Authtest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

nok, nfail: int;
alpha, p: ref Keyring->IPint;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	if(kr == nil){
		sys->print("authtest: can't load Keyring: %r\n");
		raise "fail:load";
	}
	algs := "ed25519" :: "ed25519mldsa65" :: "rsa" :: nil;
	if(args != nil && tl args != nil)
		algs = tl args;
	(alpha, p) = kr->dhparams(1024);	# only version 1 uses them

	for(; algs != nil; algs = tl algs){
		alg := hd algs;
		signer := mksigner(alg, "signer");
		if(signer == nil){
			sys->print("FAIL %s: can't make a signer key\n", alg);
			nfail++;
			continue;
		}
		srv := issue(signer, "srv");
		cli := issue(signer, "alice");
		other := issue(mksigner(alg, "othersigner"), "mallory");

		run(alg, "version 2, chacha20poly1305", cli, srv, "chacha20poly1305", nil, "alice");
		run(alg, "version 2, default algorithm", cli, srv, nil, nil, "alice");
		run(alg, "version 2, an old name means chacha20poly1305", cli, srv, "sha1/rc4_256", "sha1" :: "rc4_256" :: nil, "alice");
		run(alg, "version 2, none", cli, srv, "none", "none" :: nil, "alice");
		run(alg, "version 2, none refused", cli, srv, "none", "chacha20poly1305" :: nil, nil);
		run(alg, "version 2, certificate from another signer", other, srv, nil, nil, nil);
		run(alg, "version 2, no client key", nil, srv, nil, nil, nil);
		run(alg, "version 1, sha1/rc4_256", cli, srv, "v1/sha1/rc4_256", "v1" :: "sha1" :: "rc4_256" :: nil, "alice");
		run(alg, "version 1, none", cli, srv, "v1", "v1" :: "none" :: nil, "alice");
		run(alg, "version 1 refused by default", cli, srv, "v1", nil, nil);
	}
	sys->print("authtest: %d ok, %d failed\n", nok, nfail);
	if(nfail)
		raise "fail:failed";
}

hashpk(sk: ref Keyring->SK, buf: array of byte): ref Keyring->Certificate
{
	case sk.sa.name {
	"ed25519" or "ed25519mldsa65" =>
		return kr->sign(sk, 0, kr->sha256(buf, len buf, nil, nil), "sha256");
	}
	return kr->sign(sk, 0, kr->sha1(buf, len buf, nil, nil), "sha1");
}

mksigner(alg, name: string): ref Keyring->Authinfo
{
	info := ref Keyring->Authinfo;
	info.mysk = kr->genSK(alg, name, 1024);
	if(info.mysk == nil)
		return nil;
	info.mypk = kr->sktopk(info.mysk);
	info.spk = info.mypk;
	info.cert = hashpk(info.mysk, array of byte kr->pktostr(info.mypk));
	info.alpha = alpha;
	info.p = p;
	return info;
}

issue(signer: ref Keyring->Authinfo, name: string): ref Keyring->Authinfo
{
	if(signer == nil)
		return nil;
	info := ref Keyring->Authinfo;
	info.mysk = kr->genSKfromPK(signer.mypk, name);
	info.mypk = kr->sktopk(info.mysk);
	info.spk = signer.mypk;
	info.cert = hashpk(signer.mysk, array of byte kr->pktostr(info.mypk));
	info.alpha = alpha;
	info.p = p;
	return info;
}

# want is the name the server should learn, or nil if the attempt should fail
run(keyalg, what: string, cli, srv: ref Keyring->Authinfo, alg: string, algs: list of string, want: string)
{
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0){
		sys->print("FAIL %s: %s: pipe: %r\n", keyalg, what);
		nfail++;
		return;
	}
	done := chan of string;
	spawn server(algs, srv, fds[0], done);
	fds[0] = nil;
	# the client's end stays open until the server has finished: a write
	# to a closed pipe raises an exception, which is not what is tested here
	cauth := load Auth Auth->PATH;
	cauth->init();
	(fd, err) := cauth->client(alg, cli, fds[1]);
	got := "";
	if(fd != nil){
		msg := array of byte ("hello from the client, over " + what);
		if(sys->write(fd, msg, len msg) != len msg)
			got = sys->sprint("write: %r");
		else{
			buf := array[256] of byte;
			n := sys->read(fd, buf, len buf);
			if(n != len msg + 3 || string buf[0:3] != "re:" || string buf[3:n] != string msg)
				got = "wrong reply";
		}
	}
	sres := <-done;
	fds[1] = nil;
	if(want != nil){
		if(err != "srv" || got != nil || sres != "ok " + want){
			sys->print("FAIL %s: %s: client %q %q, server %q\n", keyalg, what, err, got, sres);
			nfail++;
			return;
		}
	}else if(fd != nil || len sres >= 3 && sres[0:3] == "ok "){
		fd = nil;
		sys->print("FAIL %s: %s: should have been refused\n", keyalg, what);
		nfail++;
		return;
	}
	if(want == nil)
		what += " (" + err + ")";
	sys->print("ok   %s: %s\n", keyalg, what);
	nok++;
}

server(algs: list of string, ai: ref Keyring->Authinfo, fd: ref Sys->FD, done: chan of string)
{
	sauth := load Auth Auth->PATH;
	sauth->init();
	(nfd, id) := sauth->server(algs, ai, fd, 0);
	if(nfd == nil){
		done <-= "refused: " + id;
		return;
	}
	buf := array[256] of byte;
	n := sys->read(nfd, buf, len buf);
	if(n > 0){
		r := array[n+3] of byte;
		r[0:] = array of byte "re:";
		r[3:] = buf[0:n];
		sys->write(nfd, r, len r);
	}
	done <-= "ok " + id;
}
