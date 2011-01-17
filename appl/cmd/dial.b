implement Dial;
include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	auth: Auth;
include "sh.m";
	sh: Sh;
	Context: import sh;

Dial: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

badmodule(p: string)
{
	sys->fprint(stderr(), "dial: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

DEFAULTALG := "none";

verbose := 0;

init(drawctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if (auth == nil)
		badmodule(Auth->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);
	sh = load Sh Sh->PATH;
	if (sh == nil)
		badmodule(Sh->PATH);

	auth->init();
	alg: string;
	keyfile: string;
	doauth := 1;
	arg->init(argv);
	arg->setusage("dial [-A] [-k keyfile] [-a alg] addr command [arg...]");
	while ((opt := arg->opt()) != 0) {
		case opt {
		'A' =>
			doauth = 0;
		'a' =>
			alg = arg->earg();
		'f' or
		'k' =>
			keyfile = arg->earg();
			if (! (keyfile[0] == '/' || (len keyfile > 2 &&  keyfile[0:2] == "./")))
				keyfile = "/usr/" + user() + "/keyring/" + keyfile;
		'v' =>
			verbose = 1;
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if (len argv < 2)
		arg->usage();
	arg = nil;
	(addr, shcmd) := (hd argv, tl argv);

	if (doauth && alg == nil)
		alg = DEFAULTALG;

	if (alg != nil && keyfile == nil) {
		kd := "/usr/" + user() + "/keyring/";
		if (exists(kd + addr))
			keyfile = kd + addr;
		else
			keyfile = kd + "default";
	}
	cert: ref Keyring->Authinfo;
	if (alg != nil) {
		cert = keyring->readauthinfo(keyfile);
		if (cert == nil) {
			sys->fprint(stderr(), "dial: cannot read %s: %r\n", keyfile);
			raise "fail:bad keyfile";
		}
	}

	(ok, c) := sys->dial(addr, nil);
	if (ok == -1) {
		sys->fprint(stderr(), "dial: cannot dial %s:: %r\n", addr);
		raise "fail:errors";
	}
	user: string;
	if (alg != nil) {
		err: string;
		(c.dfd, err) = auth->client(alg, cert, c.dfd);
		if (c.dfd == nil) {
			sys->fprint(stderr(), "dial: authentication failed: %s\n", err);
			raise "fail:errors";
		}
		user = err;
	}
	sys->dup(c.dfd.fd, 0);
	sys->dup(c.dfd.fd, 1);
	c.dfd = c.cfd = nil;
	ctxt := Context.new(drawctxt);
	if (user != nil)
		ctxt.set("user", sh->stringlist2list(user :: nil));
	else
		ctxt.set("user", nil);
	ctxt.set("net", ref Sh->Listnode(nil, c.dir) :: nil);
	ctxt.run(sh->stringlist2list(shcmd), 1);
}

exists(f: string): int
{
	(ok, nil) := sys->stat(f);
	return ok != -1;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

user(): string
{
	u := readfile("/dev/user");
	if (u == nil)
		return "nobody";
	return u;
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[0:n];	
}
