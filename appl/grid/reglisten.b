implement Listen;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

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
include "registries.m";
	registries: Registries;
	Registry, Attributes: import registries;

Listen: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

badmodule(p: string)
{
	sys->fprint(stderr(), "listen: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

serverkey: ref Keyring->Authinfo;
verbose := 0;

registered: ref Registries->Registered;

init(drawctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if (auth == nil)
		badmodule(Auth->PATH);
	sh = load Sh Sh->PATH;
	if (sh == nil)
		badmodule(Sh->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);
	auth->init();
	algs: list of string;
	arg->init(argv);
	keyfile: string;
	initscript: string;
	doauth := 1;
	synchronous := 0;
	trusted := 0;
	regattrs: list of (string, string);
	arg->setusage("listen [-i {initscript}] [-Ast] [-f keyfile] [-a alg]... addr command [arg...]");
	while ((opt := arg->opt()) != 0) {
		case opt {
		'a' =>
			algs = arg->earg() :: algs;
		'A' =>
			doauth = 0;
		'f' =>
			keyfile = arg->earg();
			if (! (keyfile[0] == '/' || (len keyfile > 2 &&  keyfile[0:2] == "./")))
				keyfile = "/usr/" + user() + "/keyring/" + keyfile;
		'i' =>
			initscript = arg->earg();
		'v' =>
			verbose = 1;
		's' =>
			synchronous = 1;
		't' =>
			trusted = 1;
		'r' =>
			a := arg->earg();
			v := arg->earg();
			regattrs = (a, v) :: regattrs;
		* =>
			arg->usage();
		}
	}
	if(regattrs != nil){
		registries = load Registries Registries->PATH;
		if(registries == nil)
			badmodule(Registries->PATH);
		registries->init();
	}

	if (doauth && algs == nil)
		algs = getalgs();
	if (algs != nil) {
		if (keyfile == nil)
			keyfile = "/usr/" + user() + "/keyring/default";
		serverkey = keyring->readauthinfo(keyfile);
		if (serverkey == nil) {
			sys->fprint(stderr(), "listen: cannot read %s: %r\n", keyfile);
			raise "fail:bad keyfile";
		}
	}
	if(!trusted){
		sys->unmount(nil, "/mnt/keys");	# should do for now
		# become none?
	}

	argv = arg->argv();
	n := len argv;
	if (n < 2)
		arg->usage();
	arg = nil;

	sync := chan[1] of string;
	spawn listen(drawctxt, hd argv, tl argv, algs, regattrs, initscript, sync);
	e := <-sync;
	if(e != nil)
		raise "fail:" + e;
	if(synchronous){
		e = <-sync;
		if(e != nil)
			raise "fail:" + e;
	}
}

listen(drawctxt: ref Draw->Context, addr: string, argv: list of string,
		algs: list of string, regattrs: list of (string, string),
		initscript: string, sync: chan of string)
{
	{
		listen1(drawctxt, addr, argv, algs, regattrs, initscript, sync);
	} exception e {
	"fail:*" =>
		sync <-= e;
	}
}

listen1(drawctxt: ref Draw->Context, addr: string, argv: list of string,
		algs: list of string, regattrs: list of (string, string),
		initscript: string, sync: chan of string)
{
	sys->pctl(Sys->FORKFD, nil);
	if(regattrs != nil){
		sys->pctl(Sys->FORKNS, nil);
		registry := Registry.new("/mnt/registry");
		if(registry == nil)
			registry = Registry.connect(nil, nil, nil);
		if(registry == nil){
			sys->fprint(stderr(), "reglisten: cannot register: %r\n");
			sync <-= "cannot register";
			exit;
		}
		err: string;
		myaddr := addr;
		(n, lst) := sys->tokenize(myaddr, "!");
		if (n == 3 && hd tl lst == "*") {
			sysname := readfile("/dev/sysname");
			if (sysname != nil && sysname[len sysname - 1] == '\n')
				sysname = sysname[:len sysname - 1];
			myaddr = hd lst + "!" + sysname + "!" + hd tl tl lst;
		}
		(registered, err) = registry.register(myaddr, Attributes.new(regattrs), 0);
		if(registered == nil){
			sys->fprint(stderr(), "reglisten: cannot register %s: %s\n", myaddr, err);
			sync <-= "cannot register";
			exit;
		}
	}

	ctxt := Context.new(drawctxt);
	(ok, acon) := sys->announce(addr);
	if (ok == -1) {
		sys->fprint(stderr(), "listen: failed to announce on '%s': %r\n", addr);
		sync <-= "cannot announce";
		exit;
	}
	ctxt.set("user", nil);
	if (initscript != nil) {
		ctxt.setlocal("net", ref Sh->Listnode(nil, acon.dir) :: nil);
		ctxt.run(ref Sh->Listnode(nil, initscript) :: nil, 0);
		initscript = nil;
	}

	# make sure the shell command is parsed only once.
	cmd := sh->stringlist2list(argv);
	if((hd argv) != nil && (hd argv)[0] == '{'){
		(c, e) := sh->parse(hd argv);
		if(c == nil){
			sys->fprint(stderr(), "listen: %s\n", e);
			sync <-= "parse error";
			exit;
		}
		cmd = ref Sh->Listnode(c, hd argv) :: tl cmd;
	}

	sync <-= nil;
	listench := chan of (int, Sys->Connection);
	authch := chan of (string, Sys->Connection);
	spawn listener(listench, acon, addr);
	for (;;) {
		user := "";
		ccon: Sys->Connection;
		alt {
		(lok, c) := <-listench =>
			if (lok == -1)
				sync <-= "listen";
			if (algs != nil) {
				spawn authenticator(authch, c, algs, addr);
				continue;
			}
			ccon = c;
		(user, ccon) = <-authch =>
			;
		}
		if (user != nil)
			ctxt.set("user", sh->stringlist2list(user :: nil));
		ctxt.set("net", ref Sh->Listnode(nil, ccon.dir) :: nil);

		# XXX could do this in a separate process too, to
		# allow new connections to arrive and start authenticating
		# while the shell command is still running.
		sys->dup(ccon.dfd.fd, 0);
		sys->dup(ccon.dfd.fd, 1);
		ccon.dfd = ccon.cfd = nil;
		ctxt.run(cmd, 0);
		sys->dup(2, 0);
		sys->dup(2, 1);
	}
}

listener(listench: chan of (int, Sys->Connection), c: Sys->Connection, addr: string)
{
	for (;;) {
		(ok, nc) := sys->listen(c);
		if (ok == -1) {
			sys->fprint(stderr(), "listen: listen error on '%s': %r\n", addr);
			listench <-= (-1, nc);
			exit;
		}
		if (verbose)
			sys->fprint(stderr(), "listen: got connection on %s from %s",
					addr, readfile(nc.dir + "/remote"));
		nc.dfd = sys->open(nc.dir + "/data", Sys->ORDWR);
		if (nc.dfd == nil)
			sys->fprint(stderr(), "listen: cannot open %s: %r\n", nc.dir + "/data");
		else
			listench <-= (ok, nc);
	}
}

authenticator(authch: chan of (string, Sys->Connection),
		c: Sys->Connection, algs: list of string, addr: string)
{
	err: string;
	(c.dfd, err) = auth->server(algs, serverkey, c.dfd, 0);
	if (c.dfd == nil) {
		sys->fprint(stderr(), "listen: auth on %s failed: %s\n", addr, err);
		return;
	}
	if (verbose)
		sys->fprint(stderr(), "listen: authenticated on %s as %s\n", addr, err);
	authch <-= (err, c);
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
