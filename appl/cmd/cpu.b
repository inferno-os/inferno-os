implement CPU;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
	Context: import Draw;
include "string.m";
	str: String;
include "arg.m";
include "keyring.m";
include "security.m";

DEFCMD:	con "/dis/sh";

CPU: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

badmodule(p: string)
{
	sys->fprint(stderr, "cpu: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

usage()
{
	sys->fprint(stderr, "Usage: cpu [-C cryptoalg] mach command args...\n");
	raise "fail:usage";
}

# The default level of security is NOSSL, unless
# the keyring directory doesn't exist, in which case
# it's disallowed.
init(nil: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg := load Arg Arg->PATH;
	if (arg == nil) badmodule(Arg->PATH);

	str = load String String->PATH;
	if (str == nil) badmodule(String->PATH);

	au := load Auth Auth->PATH;
	if (au == nil) badmodule(Auth->PATH);

	kr := load Keyring Keyring->PATH;
	if (kr == nil) badmodule(Keyring->PATH);

	arg->init(argv);
	alg := "";
	while ((opt := arg->opt()) != 0) {
		if (opt == 'C') {
			alg = arg->arg();
		} else
			usage();
	}
	argv = arg->argv();
	args := "auxi/cpuslave";
#	if(ctxt != nil && ctxt.screen != nil)
#		args += " -s" + string ctxt.screen.id;
#	else
		args += " --";

	mach: string;
	case len argv {
	0 =>
		usage();
	1 =>
		mach = hd argv;
		args += " " + DEFCMD;
	* =>
		mach = hd argv;
		args += " " + str->quoted(tl argv);
	}

	user := getuser();
	kd := "/usr/" + user + "/keyring/";
	cert := kd + netmkaddr(mach, "tcp", "");
	if (!exists(cert)) {
		cert = kd + "default";
		if (!exists(cert)) {
			sys->fprint(stderr, "cpu: cannot find certificate in %s; use getauthinfo\n", kd);
			raise "fail:no certificate";
		}
	}

	# To make visible remotely
	if(!exists("/dev/draw/new"))
		sys->bind("#d", "/dev", Sys->MBEFORE);

	(ok, c) := sys->dial(netmkaddr(mach, "net", "rstyx"), nil);
	if(ok < 0){
		sys->fprint(stderr, "Error: cpu: dial: %r\n");
		return;
	}

	ai := kr->readauthinfo(cert);

	if (alg == nil)
		alg = "none";
	err := au->init();
	if(err != nil) {
		sys->fprint(stderr, "cpu: cannot initialise auth module: %s\n", err);
		raise "fail:auth init failed";
	}

	fd := ref Sys->FD;
	#sys->fprint(stderr, "cpu: authenticating using alg '%s'\n", alg);		
	(fd, err) = au->client(alg, ai, c.dfd);
	if(fd == nil) {
		sys->fprint(stderr, "cpu: authentication failed: %s\n", err);
		raise "fail:authentication failure";
	}

	t := array of byte sys->sprint("%d\n%s\n", len (array of byte args)+1, args);
	if(sys->write(fd, t, len t) != len t){
		sys->fprint(stderr, "cpu: export args write error: %r\n");
		raise "fail:write error";
	}

	if(sys->export(fd, "/", sys->EXPWAIT) < 0){
		sys->fprint(stderr, "cpu: export failed: %r\n");
		raise "fail:export error";
	}
}

exists(file: string): int
{
	(ok, nil) := sys->stat(file);
	return ok != -1;
}

getuser(): string
{
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil){
		sys->fprint(stderr, "cpu: cannot open /dev/user: %r\n");
		raise "fail:no user id";
	}

	buf := array[50] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0){
		sys->fprint(stderr, "cpu: cannot read /dev/user: %r\n");
		raise "fail:no user id";
	}

	return string buf[0:n];	
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, nil) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}
