implement Logintest;

#
# logintest: Login->loginfd against auth/logind over a pipe, with a signer
# key and a password file made on the spot, for each kind of signer key.
# A certificate that comes back is then used to authenticate with
# Auth->client against a server holding another of the signer's
# certificates. One user's entry is a verifier in place of the SHA-1 of
# the password, and the stored entries are tried as if stolen.
# Prints one line for each case and a count; needs no
# network, so it runs anywhere, including a native kernel.
#
# usage: auth/logintest [-s] [keyalg ...]	(-s skips the 20-second silent-signer case)
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
	kr: Keyring;
include "security.m";

Logintest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

Logind: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

Password: con "correct horse battery";
nok, nfail: int;
dir: string;
alpha, p: ref Keyring->IPint;
stolen: array of byte;	# used as the secret when run is given no password

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	if(kr == nil){
		sys->print("logintest: can't load Keyring: %r\n");
		raise "fail:load";
	}
	silent := 1;
	if(args != nil)
		args = tl args;
	if(args != nil && hd args == "-s"){
		silent = 0;
		args = tl args;
	}
	algs := "ed25519mldsa65" :: "ed25519" :: "rsa" :: nil;
	if(args != nil)
		algs = args;
	(alpha, p) = kr->dhparams(1024);

	# the signer's files: a key, and a secret and an expiry time for each user
	dir = "/tmp/logintest." + string sys->pctl(0, nil);
	cleanup();	# what an interrupted run left
	mkdir(dir);
	mkdir(dir + "/keys");
	digest := array[Keyring->SHA1dlen] of byte;
	pw := array of byte Password;
	kr->sha1(pw, len pw, digest, nil);
	user("alice", digest, "never");
	user("bob", digest, "expired");
	# vera's entry is a verifier: enough to check her password, not to log in
	lg := load Login Login->PATH;
	if(lg == nil){
		sys->print("logintest: can't load Login: %r\n");
		raise "fail:load";
	}
	vera := lg->verifier("vera", digest);
	if(vera == nil || len vera != Login->Verifierlen){
		sys->print("logintest: can't make a verifier\n");
		raise "fail:verifier";
	}
	user("vera", vera, "never");

	for(; algs != nil; algs = tl algs){
		alg := hd algs;
		signer := mksigner(alg, "signer");
		if(signer == nil || kr->writeauthinfo(touch(dir + "/signerkey"), signer) < 0){
			sys->print("FAIL %s: can't make a signer key: %r\n", alg);
			nfail++;
			continue;
		}
		srv := issue(signer, "srv");

		run(alg, "version 2", 2, "alice", Password, nil, 0, srv, nil);
		run(alg, "version 2, wrong password", 2, "alice", "incorrect horse", nil, 0, srv, "name or secret incorrect");
		run(alg, "version 2, no such user", 2, "carol", Password, nil, 0, srv, "name or secret incorrect");
		run(alg, "version 2, expired user", 2, "bob", Password, nil, 0, srv, "name or secret incorrect");
		run(alg, "version 2, key exchange altered on the way", 2, "alice", Password, nil, 100, srv, "name or secret incorrect");
		run(alg, "version 2, signer that also serves version 1", 2, "alice", Password, "-1" :: nil, 0, srv, nil);
		run(alg, "version 1 refused by default", 1, "alice", Password, nil, 0, srv, "version 1 of the login protocol is not accepted");
		run(alg, "version 1, signer given -1", 1, "alice", Password, "-1" :: nil, 0, srv, nil);
		run(alg, "version 1, wrong password, signer given -1", 1, "alice", "incorrect horse", "-1" :: nil, 0, srv, "*");
		run(alg, "version 2, user with a verifier only", 2, "vera", Password, nil, 0, srv, nil);
		run(alg, "version 2, user with a verifier only, wrong password", 2, "vera", "incorrect horse", nil, 0, srv, "name or secret incorrect");
		# (version 1 has no way to tell its client why; the signer's console says)
		run(alg, "version 1, user with a verifier only, signer given -1", 1, "vera", Password, "-1" :: nil, 0, srv, "*");
		# what someone who has read the signer's files can do with each kind of entry
		stolen = digest;
		run(alg, "version 2, alice's stored SHA-1 in place of her password", 2, "alice", nil, nil, 0, srv, nil);
		stolen = vera[len Login->Verifiertag:len Login->Verifiertag+Keyring->SHA1dlen];
		run(alg, "version 2, vera's stored verifier in place of her password", 2, "vera", nil, nil, 0, srv, "name or secret incorrect");
		stolen = array[Keyring->SHA1dlen] of byte;
		kr->sha1(vera, len vera, stolen, nil);
		run(alg, "version 2, the SHA-1 of vera's entry in place of her password", 2, "vera", nil, nil, 0, srv, "name or secret incorrect");
	}
	if(silent)
		nobody();
	cleanup();
	sys->print("logintest: %d ok, %d failed\n", nok, nfail);
	if(nfail)
		raise "fail:failed";
}

cleanup()
{
	for(l := "alice" :: "bob" :: "vera" :: nil; l != nil; l = tl l){
		sys->remove(dir + "/keys/" + hd l + "/secret");
		sys->remove(dir + "/keys/" + hd l + "/expire");
		sys->remove(dir + "/keys/" + hd l);
	}
	sys->remove(dir + "/keys");
	sys->remove(dir + "/signerkey");
	sys->remove(dir);
}

mkdir(name: string)
{
	if(sys->create(name, Sys->OREAD, Sys->DMDIR|8r700) == nil){
		sys->print("logintest: can't create %s: %r\n", name);
		raise "fail:create";
	}
}

touch(name: string): string
{
	sys->create(name, Sys->OWRITE, 8r600);
	return name;
}

user(name: string, secret: array of byte, expire: string)
{
	d := dir + "/keys/" + name;
	mkdir(d);
	fd := sys->create(d + "/secret", Sys->OWRITE, 8r600);
	sys->write(fd, secret, len secret);
	fd = sys->create(d + "/expire", Sys->OWRITE, 8r600);
	sys->fprint(fd, "%s", expire);
}

signpk(sk: ref Keyring->SK, buf: array of byte): ref Keyring->Certificate
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
	info.cert = signpk(info.mysk, array of byte kr->pktostr(info.mypk));
	info.alpha = alpha;
	info.p = p;
	return info;
}

issue(signer: ref Keyring->Authinfo, name: string): ref Keyring->Authinfo
{
	info := ref Keyring->Authinfo;
	info.mysk = kr->genSKfromPK(signer.mypk, name);
	info.mypk = kr->sktopk(info.mysk);
	info.spk = signer.mypk;
	info.cert = signpk(signer.mysk, array of byte kr->pktostr(info.mypk));
	info.alpha = alpha;
	info.p = p;
	return info;
}

# want is nil if the login should succeed, else text its error must hold.
# flip, if not zero, is the client's byte in which a bit is changed on the way.
run(keyalg, what: string, version: int, name, password: string, dargs: list of string, flip: int, srv: ref Keyring->Authinfo, want: string)
{
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0){
		sys->print("FAIL %s: %s: pipe: %r\n", keyalg, what);
		nfail++;
		return;
	}
	done := chan of int;
	cfd := fds[1];
	mid: array of ref Sys->FD;
	if(flip){
		# a second pipe, and someone in the middle
		mid = array[2] of ref Sys->FD;
		sys->pipe(mid);
		spawn middle(mid[0], fds[1], flip);
		spawn middle(fds[1], mid[0], 0);
		cfd = mid[1];
	}
	spawn signer(fds[0], dargs, done);
	fds[0] = nil;
	login := load Login Login->PATH;
	if(login == nil){
		sys->print("FAIL %s: %s: can't load Login: %r\n", keyalg, what);
		nfail++;
		return;
	}
	err: string;
	info: ref Keyring->Authinfo;
	if(password == nil)
		(err, info) = login->loginsecret(version, name, stolen, cfd);
	else
		(err, info) = login->loginfd(version, name, password, cfd);
	if(info == nil){
		# a version 1 signer learns of a failure only when the client goes
		cfd = nil;
		fds[1] = nil;
		mid = nil;
	}
	<-done;
	if(want != nil){
		# "*" is any error: version 1 notices a wrong password only as rubbish
		if(info != nil || want != "*" && !contains(err, want)){
			sys->print("FAIL %s: %s: got %q\n", keyalg, what, err);
			nfail++;
		}else{
			if(want == "*")
				err = "refused";
			sys->print("ok   %s: %s (%s)\n", keyalg, what, err);
			nok++;
		}
		return;
	}
	if(info == nil){
		sys->print("FAIL %s: %s: %s\n", keyalg, what, err);
		nfail++;
		return;
	}
	if(info.mypk.owner != name || info.mysk == nil || info.cert == nil || info.spk == nil || info.alpha == nil || info.p == nil){
		sys->print("FAIL %s: %s: incomplete authinfo\n", keyalg, what);
		nfail++;
		return;
	}
	# the certificate must be good for auth(6)
	e := authenticate(info, srv, name);
	if(e != nil){
		sys->print("FAIL %s: %s: the certificate does not authenticate: %s\n", keyalg, what, e);
		nfail++;
		return;
	}
	sys->print("ok   %s: %s, and its certificate authenticates\n", keyalg, what);
	nok++;
}

# a signer that says nothing, as one with only version 1 does to a version 2 client
nobody()
{
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	login := load Login Login->PATH;
	(err, info) := login->loginfd(2, "alice", Password, fds[1]);
	if(info == nil && contains(err, "no answer")){
		sys->print("ok   a signer that does not answer (%s)\n", err);
		nok++;
	}else{
		sys->print("FAIL a signer that does not answer: %q\n", err);
		nfail++;
	}
}

signer(fd: ref Sys->FD, dargs: list of string, done: chan of int)
{
	# only its end of the pipe: a copy of the client's would keep the pipe open
	sys->pctl(Sys->NEWFD, fd.fd :: nil);
	sys->dup(fd.fd, 0);
	fd = nil;
	logind := load Logind "/dis/auth/logind.dis";
	if(logind == nil)
		sys->print("logintest: can't load logind: %r\n");
	else
		logind->init(nil, "logind" :: "-k" :: dir + "/keys" :: "-s" :: dir + "/signerkey" :: dargs);
	# a signer that gives up says so by hanging up: let go of the connection
	# now, as its process ending would, whatever is still awaiting collection
	logind = nil;
	sys->pctl(Sys->NEWFD, 2 :: nil);
	done <-= 1;
}

middle(src, dst: ref Sys->FD, flip: int)
{
	buf := array[8192] of byte;
	seen := 0;
	while((n := sys->read(src, buf, len buf)) > 0){
		if(flip && flip >= seen && flip < seen+n)
			buf[flip-seen] ^= byte 1;
		seen += n;
		{
			if(sys->write(dst, buf, n) != n)
				break;
		}exception{
		"write on closed pipe" =>
			break;
		}
	}
}

authenticate(cli, srv: ref Keyring->Authinfo, name: string): string
{
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	done := chan of string;
	spawn authserver(srv, fds[0], done);
	fds[0] = nil;
	auth := load Auth Auth->PATH;
	auth->init();
	(fd, err) := auth->client(nil, cli, fds[1]);
	sres := <-done;
	if(fd == nil)
		return "client: " + err;
	if(sres != "ok " + name)
		return "server: " + sres;
	return nil;
}

authserver(ai: ref Keyring->Authinfo, fd: ref Sys->FD, done: chan of string)
{
	auth := load Auth Auth->PATH;
	auth->init();
	(nfd, id) := auth->server(nil, ai, fd, 0);
	if(nfd == nil)
		done <-= "refused: " + id;
	else
		done <-= "ok " + id;
}

contains(s, t: string): int
{
	for(i := 0; i + len t <= len s; i++)
		if(s[i:i+len t] == t)
			return 1;
	return 0;
}
