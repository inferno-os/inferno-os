implement Mount;

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
include "security.m";
include "dial.m";
	dial: Dial;
include "factotum.m";
include "styxconv.m";
include "styxpersist.m";
include "arg.m";
include "sh.m";

Mount: module
{
	init:	 fn(nil: ref Draw->Context, nil: list of string);
};

verbose := 0;
doauth := 1;
do9 := 0;
oldstyx := 0;
persist := 0;
showstyx := 0;
quiet := 0;

alg := "none";
keyfile: string;
spec: string;
addr: string;

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
        dial = load Dial Dial->PATH;
        if(dial == nil)
                 nomod(Dial->PATH);
	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);

	arg->init(args);
	arg->setusage("mount [-a|-b] [-coA9] [-C cryptoalg] [-k keyfile] [-q] net!addr|file|{command} mountpoint [spec]");
	flags := 0;
	while((o := arg->opt()) != 0){
		case o {
		'a' =>
			flags |= Sys->MAFTER;
		'b' =>
			flags |= Sys->MBEFORE;
		'c' =>
			flags |= Sys->MCREATE;
		'C' =>
			alg = arg->earg();
		'k' or
		'f' =>
			keyfile = arg->earg();
		'A' =>
			doauth = 0;
		'9' =>
			doauth = 0;
			do9 = 1;
		'o' =>
			oldstyx = 1;
		'v' =>
			verbose = 1;
		'P' =>
			persist = 1;
		'S' =>
			showstyx = 1;
		'q' =>
			quiet = 1;
		*   =>
			arg->usage();
		}
	}
	args = arg->argv();
	if(len args != 2){
		if(len args != 3)
			arg->usage();
		spec = hd tl tl args;
	}
	arg = nil;
	addr = hd args;
	mountpoint := hd tl args;

	if(oldstyx && do9)
		fail("usage", "cannot combine -o and -9 options");

	fd := connect(ctxt, addr);
	ok: int;
	if(do9){
		fd = styxlog(fd);
		factotum := load Factotum Factotum->PATH;
		if(factotum == nil)
			nomod(Factotum->PATH);
		factotum->init();
		ok = factotum->mount(fd, mountpoint, flags, spec, keyfile).t0;
	}else{
		err: string;
		if(!persist){
			(fd, err) = authcvt(fd);
			if(fd == nil)
				fail("error", err);
		}
		fd = styxlog(fd);
		ok = sys->mount(fd, nil, mountpoint, flags, spec);
	}
	if(ok < 0 && !quiet)
		fail("mount failed", sys->sprint("mount failed: %r"));
}

connect(ctxt: ref Draw->Context, dest: string): ref Sys->FD
{
	if(dest != nil && dest[0] == '{' && dest[len dest - 1] == '}'){
		if(persist)
			fail("usage", "cannot persistently mount a command");
		doauth = 0;
		return popen(ctxt, dest :: nil);
	}
	(n, nil) := sys->tokenize(dest, "!");
	if(n == 1){
		fd := sys->open(dest, Sys->ORDWR);
		if(fd != nil){
			if(persist)
				fail("usage", "cannot persistently mount a file");
			return fd;
		}
		if(dest[0] == '/')
			fail("open failed", sys->sprint("can't open %s: %r", dest));
	}
	svc := "styx";
	if(do9)
		svc = "9fs";
	dest = dial->netmkaddr(dest, "net", svc);
	if(persist){
		styxpersist := load Styxpersist Styxpersist->PATH;
		if(styxpersist == nil)
			fail("load", sys->sprint("cannot load %s: %r", Styxpersist->PATH));
		sys->pipe(p := array[2] of ref Sys->FD);
		(c, err) := styxpersist->init(p[0], do9, nil);
		if(c == nil)
			fail("error", "styxpersist: "+err);
		spawn dialler(c, dest);
		return p[1];
	}
	c := dial->dial(dest, nil);
	if(c == nil)
			fail("dial failed",  sys->sprint("can't dial %s: %r", dest));
	return c.dfd;
}

dialler(dialc: chan of chan of ref Sys->FD, dest: string)
{
	while((reply := <-dialc) != nil){
		if(verbose)
			sys->print("dialling %s\n", addr);
		c := dial->dial(dest, nil);
		if(c == nil){
			reply <-= nil;
			continue;
		}
		(fd, err) := authcvt(c.dfd);
		if(fd == nil && verbose)
			sys->print("%s\n", err);
		# XXX could check that user at the other end is still the same.
		reply <-= fd;
	}
}

authcvt(fd: ref Sys->FD): (ref Sys->FD, string)
{
	err: string;
	if(doauth){
		(fd, err) = authenticate(keyfile, alg, fd, addr);
		if(fd == nil)
			return (nil, err);
		if(verbose)
			sys->print("remote username is %s\n", err);
	}
	if(oldstyx)
		return cvstyx(fd);
	return (fd, nil);
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

runcmd(sh: Sh, ctxt: ref Draw->Context, argv: list of string, stdin: ref Sys->FD, sync: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sync <-= 0;
	sh->run(ctxt, argv);
}

cvstyx(fd: ref Sys->FD): (ref Sys->FD, string)
{
	styxconv := load Styxconv Styxconv->PATHNEW2OLD;
	if(styxconv == nil)
		return (nil, sys->sprint("cannot load %s: %r", Styxconv->PATHNEW2OLD));
	styxconv->init();
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		return (nil, sys->sprint("can't create pipe: %r"));
	spawn styxconv->styxconv(p[1], fd);
	p[1] = nil;
	return (p[0], nil);
}

authenticate(keyfile, alg: string, dfd: ref Sys->FD, addr: string): (ref Sys->FD, string)
{
	cert : string;

	kr := load Keyring Keyring->PATH;
	if(kr == nil)
		return (nil, sys->sprint("cannot load %s: %r", Keyring->PATH));

	kd := "/usr/" + user() + "/keyring/";
	if(keyfile == nil) {
		cert = kd + dial->netmkaddr(addr, "tcp", "");
		(ok, nil) := sys->stat(cert);
		if (ok < 0)
			cert = kd + "default";
	}
	else if(len keyfile > 0 && keyfile[0] != '/')
		cert = kd + keyfile;
	else
		cert = keyfile;
	ai := kr->readauthinfo(cert);
	if(ai == nil)
		return (nil, sys->sprint("cannot read %s: %r", cert));

	auth := load Auth Auth->PATH;
	if(auth == nil)
		nomod(Auth->PATH);

	err := auth->init();
	if(err != nil)
		return (nil, "cannot init auth: "+err);

	fd: ref Sys->FD;
	(fd, err) = auth->client(alg, ai, dfd);
	if(fd == nil)
		return (nil, "authentication failed: "+err);
	return (fd, err);
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

kill(pid: int)
{
	if ((fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "kill");
}

include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;

styxlog(fd: ref Sys->FD): ref Sys->FD
{
	if(showstyx){
		sys->pipe(p := array[2] of ref Sys->FD);
		styx = load Styx Styx->PATH;
		styx->init();
		spawn tmsgreader(p[0], fd, p1 := chan[1] of int, p2 := chan[1] of int);
		spawn rmsgreader(fd, p[0], p2, p1);
		fd = p[1];
	}
	return fd;
}

tmsgreader(cfd, sfd: ref Sys->FD, p1, p2: chan of int)
{
	p1 <-= sys->pctl(0, nil);
	m: ref Tmsg;
	do{
		m = Tmsg.read(cfd, 9000);
		sys->print("%s\n", m.text());
		d := m.pack();
		if(sys->write(sfd, d, len d) != len d)
			sys->print("tmsg write error: %r\n");
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
	kill(<-p2);
}

rmsgreader(sfd, cfd: ref Sys->FD, p1, p2: chan of int)
{
	p1 <-= sys->pctl(0, nil);
	m: ref Rmsg;
	do{
		m = Rmsg.read(sfd, 9000);
		sys->print("%s\n", m.text());
		d := m.pack();
		if(sys->write(cfd, d, len d) != len d)
			sys->print("rmsg write error: %r\n");
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
	kill(<-p2);
}
