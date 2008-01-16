implement Mount;

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
include "security.m";
include "arg.m";
include "sh.m";
include "styxconv.m";
	styxconv: Styxconv;

Mount: module
{
	init:	 fn(nil: ref Draw->Context, nil: list of string);
};

vflag := 0;
doauth := 1;

usage()
{
	sys->fprint(sys->fildes(2), "Usage: mount [-a|-b] [-cA] [-C cryptoalg] [-f keyfile] net!addr|file|{command} mountpoint [spec]\n");
	raise "fail:usage";
}

fail(status, msg: string)
{
	sys->fprint(sys->fildes(2), "mount: %s\n", msg);
	raise "fail:"+status;
}

nomod(mod: string)
{
	fail("load", sys->sprint("can't load %s: %r", mod));
}

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	vflag = 0;
	unauth := 0;
	alg := "none";
	keyfile: string;
	spec: string;

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	styxconv = load Styxconv Styxconv->PATH;
	if(styxconv == nil)
		nomod(Styxconv->PATH);

	arg->init(args);
	styxconv->init();

	flags := 0;
	while((o := arg->opt()) != 0)
		case o {
		'a' =>
			flags |= Sys->MAFTER;
		'b' =>
			flags |= Sys->MBEFORE;
		'c' =>
			flags |= Sys->MCREATE;
		'C' =>
			alg = arg->arg();
			if(alg == nil)
				usage();
		'f' =>
			keyfile = arg->arg();
			if(keyfile == nil)
				usage();
		'A' =>
			doauth = 0;
		'v' =>
			vflag = 1;
		'u' =>
			unauth = 1;	# temporary, undocumented option for testing
		*   =>
			usage();
		}
	args = arg->argv();
	arg = nil;
	if(len args != 2){
		if(len args != 3)
			usage();
		spec = hd tl tl args;
	}
	addr := hd args;
	mountpoint := hd tl args;

	# open stream
	fd := do_connect(ctxt, addr);

	# authenticate if necessary
	if (doauth)
		fd = do_auth(keyfile, alg, fd, addr, unauth);

	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		fail("can't create pipe", sys->sprint("can't create pipe: %r"));
	pidch := chan of int;
	spawn styxconv->styxconv(p[1], fd, pidch);
	p[1] = nil;
	<- pidch;
	ok := sys->mount(p[0], nil, mountpoint, flags, spec);
	p[0] = nil;
	if(ok < 0)
		fail("mount failed", sys->sprint("mount failed: %r"));
	
}

# either make network connection or open file
do_connect(ctxt: ref Draw->Context, dest: string): ref Sys->FD
{
	if(dest != nil && dest[0] == '{' && dest[len dest - 1] == '}'){
		doauth = 0;
		return popen(ctxt, dest :: nil);
	}
	(n, nil) := sys->tokenize(dest, "!");
	if(n == 1){
		fd := sys->open(dest, Sys->ORDWR);
		if(fd != nil)
			return fd;
		if(dest[0] == '/')
			fail("open failed", sys->sprint("can't open %s: %r", dest));
	}
	(ok, c) := sys->dial(netmkaddr(dest, "net", "styx"), nil);
	if(ok < 0)
			fail("dial failed",  sys->sprint("can't dial %s: %r", dest));
	return c.dfd;
}

popen(ctxt: ref Draw->Context, argv: list of string): ref Sys->FD
{
	sh := load Sh Sh->PATH;
	if(sh == nil)
		nomod(Sh->PATH);
	sync := chan of int;
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	spawn runcmd(sh, ctxt, argv, fds[0], sync);
	<-sync;
	return fds[1];
}

runcmd(sh: Sh, ctxt: ref Draw->Context, argv: list of string, stdin: ref Sys->FD,
		sync: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sync <-= 0;
	sh->run(ctxt, argv);
}

# authenticate if necessary
do_auth(keyfile, alg: string, dfd: ref Sys->FD, addr: string, unauth: int): ref Sys->FD
{
	cert : string;

	kr := load Keyring Keyring->PATH;
	if(kr == nil)
		nomod(Keyring->PATH);

	kd := "/usr/" + user() + "/keyring/";
	if (keyfile == nil) {
		cert = kd + netmkaddr(addr, "tcp", "");
		(ok, nil) := sys->stat(cert);
		if (ok < 0)
			cert = kd + "default";
	}
	else if (len keyfile > 0 && keyfile[0] != '/')
		cert = kd + keyfile;
	else
		cert = keyfile;
	ai := kr->readauthinfo(cert);
	if (ai == nil){
		if(!unauth)
			fail("readauthinfo failed", sys->sprint("cannot read %s: %r", cert));
		sys->fprint(sys->fildes(2), "mount: can't read %s (%r): trying mount as `nobody'\n", cert);
	}

	au := load Auth Auth->PATH;
	if(au == nil)
		nomod(Auth->PATH);

	err := au->init();
	if(err != nil)
		fail("auth init failed", sys->sprint("cannot init Auth: %s", err));

	fd: ref Sys->FD;
	(fd, err) = au->client(alg, ai, dfd);
	if(fd == nil)
		fail("auth failed", sys->sprint("authentication failed: %s", err));
	if(vflag)
		sys->print("remote username is %s\n", err);

	return fd;
}

user(): string
{
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

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
