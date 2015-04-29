implement Rcmd;

include "sys.m";
include "draw.m";
include "arg.m";
include "keyring.m";
include "dial.m";
include "security.m";

Rcmd: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

DEFAULTALG := "none";
sys: Sys;
auth: Auth;
dial: Dial;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;
	if(dial == nil)
		badmodule(Dial->PATH);
	arg := load Arg Arg->PATH;
	if(arg == nil)
		badmodule(Arg->PATH);
	arg->init(argv);
	alg: string;
	doauth := 1;
	exportpath := "/";
	keyfile: string;
	arg->setusage("rcmd [-A] [-f keyfile] [-e alg] [-x exportpath] tcp!mach cmd");
	while((o := arg->opt()) != 0)
		case o {
		'e' or 'a' =>
			alg = arg->earg();
		'A' =>
			doauth = 0;
		'x' =>
			exportpath = arg->earg();
			(n, nil) := sys->stat(exportpath);
			if (n == -1 || exportpath == nil)
				arg->usage();
		'f' =>
			keyfile = arg->earg();
			if (! (keyfile[0] == '/' || (len keyfile > 2 &&  keyfile[0:2] == "./")))
				keyfile = "/usr/" + user() + "/keyring/" + keyfile;
		*   =>
			arg->usage();
		}

	argv = arg->argv();
	if(argv == nil)
		arg->usage();
	arg = nil;

	if (doauth && alg == nil)
		alg = DEFAULTALG;

	addr := hd argv;
	argv = tl argv;

	args := "";
	while(argv != nil){
		args += " " + hd argv;
		argv = tl argv;
	}
	if(args == "")
		args = "sh";

	kr: Keyring;
	au: Auth;
	if (doauth) {
		kr = load Keyring Keyring->PATH;
		if(kr == nil)
			badmodule(Keyring->PATH);
		au = load Auth Auth->PATH;
		if(au == nil)
			badmodule(Auth->PATH);
		if (keyfile == nil)
			keyfile = "/usr/" + user() + "/keyring/default";
	}

	c := dial->dial(dial->netmkaddr(addr, "tcp", "rstyx"), nil);
	if(c == nil)
		error(sys->sprint("dial %s failed: %r", addr));

	fd := c.dfd;
	if (doauth) {
		ai := kr->readauthinfo(keyfile);
		#
		# let auth->client handle nil ai
		# if(ai == nil){
		#	sys->fprint(stderr(), "rcmd: certificate for %s not found\n", addr);
		#	raise "fail:no certificate";
		# }
		#

		err := au->init();
		if(err != nil)
			error(err);

		(fd, err) = au->client(alg, ai, c.dfd);
		if(fd == nil){
			sys->fprint(stderr(), "rcmd: authentication failed: %s\n", err);
			raise "fail:auth failed";
		}
	}
	t := array of byte sys->sprint("%d\n%s\n", len (array of byte args)+1, args);
	if(sys->write(fd, t, len t) != len t){
		sys->fprint(stderr(), "rcmd: cannot write arguments: %r\n");
		raise "fail:bad arg write";
	}

	if(sys->export(fd, exportpath, sys->EXPWAIT) < 0) {
		sys->fprint(stderr(), "rcmd: export: %r\n");
		raise "fail:export failed";
	}
}

exists(f: string): int
{
	(ok, nil) := sys->stat(f);
	return ok >= 0;
}

user(): string
{
	sys = load Sys Sys->PATH;

	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n];	
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

badmodule(p: string)
{
	sys->fprint(stderr(), "rcmd: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

error(e: string)
{
	sys->fprint(stderr(), "rcmd: %s\n", e);
	raise "fail:errors";
}
