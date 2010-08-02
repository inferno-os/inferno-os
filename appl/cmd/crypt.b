implement Crypt;

# encrypt/decrypt from stdin to stdout

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	ssl: SSL;
include "bufio.m";
include "msgio.m";
	msgio: Msgio;
include "arg.m";

Crypt: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Ehungup: con "i/o on hungup channel";

ALGSTR: con "alg ";
DEFAULTALG: con "md5/ideacbc";
usage()
{
	sys->fprint(stderr, "usage: crypt [-?] [-d] [-k secret] [-f secretfile] [-a alg[/alg]]\n");
	sys->fprint(stderr, "available algorithms:\n");
	showalgs(stderr);
	fail("bad usage");
}

badmodule(m: string)
{
	sys->fprint(stderr, "crypt: cannot load %s: %r\n", m);
	fail("bad module");
}

headers: con 1;
verbose := 0;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	ssl = load SSL SSL->PATH;
	if (ssl == nil)
		badmodule(SSL->PATH);
	keyring = load Keyring Keyring->PATH;
	if (keyring == nil)
		badmodule(SSL->PATH);
	msgio = load Msgio Msgio->PATH;
	msgio->init();

	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(SSL->PATH);

	decrypt := 0;
	secret: array of byte;
	alg := DEFAULTALG;

	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'd' =>
			decrypt = 1;
		'k' =>
			if ((s := arg->arg()) == nil)
				usage();
			secret = array of byte s;
		'f' =>
			if ((f := arg->arg()) == nil)
				usage();
			secret = readfile(f);
		'a' =>
			if ((alg = arg->arg()) == nil)
				usage();
		'?' =>
			showalgs(sys->fildes(1));
			return;
		'v' =>
			verbose = 1;
		* =>
			usage();
		}
	}
	argv = arg->argv();
	if (argv != nil)
		usage();
	if(secret == nil)
		secret = array of byte readpassword();
	sk := array[Keyring->SHA1dlen] of byte;
	keyring->sha1(secret, len secret, sk, nil);
	if (headers) {
		# deal with header - the header encodes the algorithm along with the data.
		if (decrypt) {
			msg := msgio->getmsg(sys->fildes(0));
			if (msg != nil)
				alg = string msg;
			if (msg == nil || len alg < len ALGSTR || alg[0:len ALGSTR] != ALGSTR)
				error("couldn't get decrypt algorithm");
			alg = alg[len ALGSTR:];
		} else {
			msg := array of byte ("alg " + alg);
			e := msgio->sendmsg(sys->fildes(1),  msg, len msg);
			if (e == -1)
				error("couldn't write algorithm string");
		}
	}
	fd := docrypt(decrypt, alg, sk);
	if (decrypt) {
		# if decrypting, don't use stream, as we want to catch
		# decryption or checksum errors when they happen.
		buf := array[Sys->ATOMICIO] of byte;
		stdout := sys->fildes(1);
		while ((n := sys->read(fd, buf, len buf)) > 0)
			sys->write(stdout, buf, n);

		if (n == -1) {
			err := sys->sprint("%r");
			if (err != Ehungup) 
				error("decryption failed: " + err);
		}
	} else {
		stream(fd, sys->fildes(1), Sys->ATOMICIO);
	}
}

docrypt(decrypt: int, alg: string, sk: array of byte): ref Sys->FD
{
	if (verbose)
		sys->fprint(stderr, "%scrypting with alg %s\n", (array[] of {"en", "de"})[decrypt!=0], alg);
	(err, fds, nil, nil) := cryptpipe(decrypt, alg, sk);
	if (err != nil)
		error(err);

	spawn stream(sys->fildes(0), fds[1], Sys->ATOMICIO);
	return fds[0];
}

# set up an encrypt/decrypt session; if decrypt is non-zero, then
# decrypt, else encrypt. alg is the algorithm to use; sk is the
# used as the secret key. 
# returns tuple (err, fds, cfd, dir)
# where err is non-nil on failure;
# otherwise fds is an array of two fds; writing to fds[1] will make
# crypted/decrypted data available to be read on fds[0].
# dir is the ssl directory in question.
cryptpipe(decrypt: int, alg: string, sk: array of byte): (string, array of ref Sys->FD, ref Sys->FD, string)
{
	pfd := array[2] of ref Sys->FD;
	if (sys->pipe(pfd) == -1)
		return ("pipe failed", nil, nil, nil);

	(err, c) := ssl->connect(pfd[1]);
	if (err != nil)
		return ("could not connect ssl: "+err, nil, nil, nil);
	pfd[1] = nil;
	err = ssl->secret(c, sk, sk);
	if (err != nil) 
		return ("could not write secret: "+err, nil, nil, nil);

	if (alg != nil)
		if (sys->fprint(c.cfd, "alg %s", alg) == -1)
			return (sys->sprint("bad algorithm %s: %r", alg), nil, nil, nil);

	fds := array[2] of ref Sys->FD;
	if (decrypt) {
		fds[1] = pfd[0];
		fds[0] = c.dfd;
	} else {
		fds[1] = c.dfd;
		fds[0] = pfd[0];
	}
	return (nil, fds, c.cfd, c.dir);
}

algnames := array[] of {("crypt", "encalgs"), ("hash", "hashalgs")};

# find available algorithms and return as tuple of two lists:
# (err, hashalgs, cryptalgs)
algs(): (string, array of list of string)
{
	(err, nil, nil, dir) := cryptpipe(0, nil, array[100] of byte);
	if (err != nil)
		return (err, nil);
	alglists := array[len algnames] of list of string;
	for (i := 0; i < len algnames; i++) {
		(nil, f) := algnames[i];
		(nil, alglists[i]) = sys->tokenize(string readfile(dir + "/"  + f), " ");
	}
	return (nil, alglists);
}

showalgs(fd: ref Sys->FD)
{
	(err, alglists) := algs();
	if (err != nil)
		error("cannot get algorithms: " + err);
	for (j := 0; j < len alglists; j++) {
		(name, nil) := algnames[j];
		sys->fprint(fd, "%s:", name);
		for (l := alglists[j]; l != nil; l = tl l)
			sys->fprint(fd, " %s", hd l);
		sys->fprint(fd, "\n");
	}
}

readpassword(): string
{
	bufio := load Bufio Bufio->PATH;
	Iobuf: import bufio;
	stdin := bufio->open("/dev/cons", Sys->OREAD);

	cfd := sys->open("/dev/consctl", Sys->OWRITE);
	if (cfd == nil || sys->fprint(cfd, "rawon") <= 0)
		sys->fprint(stderr, "crypt: warning: cannot hide typed password\n");
	sys->fprint(stderr, "password: ");
	s := "";
	while ((c := stdin.getc()) >= 0 && c != '\n'){
		case c {
		'\b' =>
			if (len s > 0)
				s = s[0:len s - 1];
		8r25 =>		# ^U
			s = nil;
		* =>
			s[len s] = c;
		}
	}
	sys->fprint(stderr, "\n");
	return s;
}

stream(src, dst: ref Sys->FD, bufsize: int)
{
	sys->stream(src, dst, bufsize);
}

readfile(f: string): array of byte
{
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil)
		error(sys->sprint("cannot read %s: %r", f));
	buf := array[8192] of byte;	# >8K key? get real!
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return nil;
	return buf[0:n];
}

error(s: string)
{
	sys->fprint(stderr, "crypt: %s\n", s);
	fail("error");
}

fail(e: string)
{
	raise "fail: "+e;
}
