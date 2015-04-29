implement Styxlisten;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	auth: Auth;
include "registries.m";
	registries: Registries;
	Registry, Service, Attributes: import registries;
include "dial.m";
	dial: Dial;
include "arg.m";
include "sh.m";

Styxlisten: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

badmodule(p: string)
{
	sys->fprint(stderr(), "styxlisten: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

verbose := 0;
registered: ref Registries->Registered;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	auth = load Auth Auth->PATH;
	if (auth == nil)
		badmodule(Auth->PATH);
	if ((e := auth->init()) != nil)
		error("auth init failed: " + e);
	keyring = load Keyring Keyring->PATH;
	if (keyring == nil)
		badmodule(Keyring->PATH);
	dial = load Dial Dial->PATH;
	if (dial == nil)
		badmodule(Dial->PATH);

	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);

	arg->init(argv);
	arg->setusage("styxlisten [-a alg]... [-Atsv] [-r attr val]... [-f keyfile] address cmd [arg...]");

	algs: list of string;
	doauth := 1;
	synchronous := 0;
	trusted := 0;
	keyfile := "";
	regattrs: list of (string, string);

	while ((opt := arg->opt()) != 0) {
		case opt {
		'v' =>
			verbose = 1;
		'a' =>
			algs = arg->earg() :: algs;
		'f' =>
			keyfile = arg->earg();
			if (! (keyfile[0] == '/' || (len keyfile > 2 &&  keyfile[0:2] == "./")))
				keyfile = "/usr/" + user() + "/keyring/" + keyfile;
		't' =>
			trusted = 1;
		'r' =>
			a := arg->earg();
			v := arg->earg();
			regattrs = (a, v) :: regattrs;
		's' =>
			synchronous = 1;
		'A' =>
			doauth = 0;
		}
	}
	argv = arg->argv();
	if (len argv < 2)
		arg->usage();
	arg = nil;
	if(regattrs != nil){
		registries = load Registries Registries->PATH;
		if(registries == nil)
			badmodule(Registries->PATH);
		registries->init();
	}

	if (doauth && algs == nil)
		algs = getalgs();
	addr := dial->netmkaddr(hd argv, "tcp", "styx");
	cmd := tl argv;

	authinfo: ref Keyring->Authinfo;
	if (doauth) {
		if (keyfile == nil)
			keyfile = "/usr/" + user() + "/keyring/default";
		authinfo = keyring->readauthinfo(keyfile);
		if (authinfo == nil)
			error(sys->sprint("cannot read %s: %r", keyfile));
	}

	c := dial->announce(addr);
	if (dial == nil)
		error(sys->sprint("cannot announce on %s: %r", addr));

	if(regattrs != nil){
		registry := Registry.new("/mnt/registry");
		if(registry == nil)
			registry = Registry.connect(nil, nil, nil);
		if(registry == nil)
			error(sys->sprint("cannot register: %r"));
		err: string;
		(registered, err) = registry.register(addr, Attributes.new(regattrs), 0);
		if(registered == nil)
			error("cannot register "+addr+": "+err);
	}
	if(!trusted){
		sys->unmount(nil, "/mnt/keys");	# should do for now
		# become none?
	}

	lsync := chan[1] of int;
	if(synchronous)
		listener(c, popen(ctxt, cmd, lsync), authinfo, algs, lsync);
	else
		spawn listener(c, popen(ctxt, cmd, lsync), authinfo, algs, lsync);
}

listener(c: ref Sys->Connection, mfd: ref Sys->FD, authinfo: ref Keyring->Authinfo, algs: list of string, lsync: chan of int)
{
	lsync <-= sys->pctl(0, nil);
	for (;;) {
		nc := dial->listen(c);
		if (nc == nil)
			error(sys->sprint("listen failed: %r"));
		if (verbose)
			sys->fprint(stderr(), "styxlisten: got connection from %s",
					readfile(nc.dir + "/remote"));
		dfd := dial->accept(nc);
		if (dfd != nil) {
			if (algs == nil) {
				sync := chan of int;
				spawn exportproc(sync, mfd, nil, dfd);
				<-sync;
			} else
				spawn authenticator(dfd, authinfo, mfd, algs);
		}
	}
}

# authenticate a connection and set the user id.
authenticator(dfd: ref Sys->FD, authinfo: ref Keyring->Authinfo, mfd: ref Sys->FD, algs: list of string)
{
	# authenticate and change user id appropriately
	(fd, err) := auth->server(algs, authinfo, dfd, 1);
	if (fd == nil) {
		if (verbose)
			sys->fprint(stderr(), "styxlisten: authentication failed: %s\n", err);
		return;
	}
	if (verbose)
		sys->fprint(stderr(), "styxlisten: client authenticated as %s\n", err);
	sync := chan of int;
	spawn exportproc(sync, mfd, err, dfd);
	<-sync;
}

exportproc(sync: chan of int, fd: ref Sys->FD, uname: string, dfd: ref Sys->FD)
{
	sys->pctl(Sys->NEWFD | Sys->NEWNS, 2 :: fd.fd :: dfd.fd :: nil);
	fd = sys->fildes(fd.fd);
	dfd = sys->fildes(dfd.fd);
	sync <-= 1;

	# XXX unfortunately we cannot pass through the aname from
	# the original attach, an inherent shortcoming of this scheme.
	if (sys->mount(fd, nil, "/", Sys->MREPL|Sys->MCREATE, nil) == -1)
		error(sys->sprint("cannot mount for user '%s': %r\n", uname));

	sys->export(dfd, "/", Sys->EXPWAIT);
}

error(e: string)
{
	sys->fprint(stderr(), "styxlisten: %s\n", e);
	raise "fail:error";
}
	
popen(ctxt: ref Draw->Context, argv: list of string, lsync: chan of int): ref Sys->FD
{
	sync := chan of int;
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	spawn runcmd(ctxt, argv, fds[0], sync, lsync);
	<-sync;
	return fds[1];
}

runcmd(ctxt: ref Draw->Context, argv: list of string, stdin: ref Sys->FD,
		sync: chan of int, lsync: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sync <-= 0;
	sh := load Sh Sh->PATH;
	e := sh->run(ctxt, argv);
	kill(<-lsync, "kill");		# kill listener, as command has exited
	if(verbose){
		if(e != nil)
			sys->fprint(stderr(), "styxlisten: command exited with error: %s\n", e);
		else
			sys->fprint(stderr(), "styxlisten: command exited\n");
	}
}

kill(pid: int, how: string)
{
	sys->fprint(sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE), "%s", how);
}

user(): string
{
	if ((s := readfile("/dev/user")) == nil)
		return "none";
	return s;
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[0:n];	
}

getalgs(): list of string
{
	sslctl := readfile("#D/clone");
	if (sslctl == nil) {
		sslctl = readfile("#D/ssl/clone");
		if (sslctl == nil)
			return nil;
		sslctl = "#D/ssl/" + sslctl;
	} else
		sslctl = "#D/" + sslctl;
	(nil, algs) := sys->tokenize(readfile(sslctl + "/encalgs") + " " + readfile(sslctl + "/hashalgs"), " \t\n");
	return "none" :: algs;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
