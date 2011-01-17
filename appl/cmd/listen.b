implement Listen;
include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	auth: Auth;
include "dial.m";
	dial: Dial;
include "sh.m";
	sh: Sh;
	Context: import sh;

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

init(drawctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if (auth == nil)
		badmodule(Auth->PATH);
	dial = load Dial Dial->PATH;
	if (dial == nil)
		badmodule(Dial->PATH);
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
	arg->setusage("listen [-i {initscript}] [-Ast] [-k keyfile] [-a alg]... addr command [arg...]");
	while ((opt := arg->opt()) != 0) {
		case opt {
		'a' =>
			algs = arg->earg() :: algs;
		'A' =>
			doauth = 0;
		'f' or
		'k' =>
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
		* =>
			arg->usage();
		}
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
	spawn listen(drawctxt, hd argv, tl argv, algs,  initscript, sync);
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
		algs: list of string, initscript: string, sync: chan of string)
{
	{
		listen1(drawctxt, addr, argv, algs, initscript, sync);
	} exception e {
	"fail:*" =>
		sync <-= e;
	}
}

listen1(drawctxt: ref Draw->Context, addr: string, argv: list of string,
		algs: list of string, initscript: string, sync: chan of string)
{
	sys->pctl(Sys->FORKFD, nil);

	ctxt := Context.new(drawctxt);
	acon := dial->announce(addr);
	if (acon == nil) {
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
	listench := chan of ref Dial->Connection;
	authch := chan of (string, ref Dial->Connection);
	spawn listener(listench, acon, addr);
	for (;;) {
		user := "";
		ccon: ref Dial->Connection;
		alt {
		c := <-listench =>
			if (c == nil){
				sync <-= "listen";
				exit;
			}
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

listener(listench: chan of ref Dial->Connection, c: ref Dial->Connection, addr: string)
{
	for (;;) {
		nc := dial->listen(c);
		if (nc == nil) {
			sys->fprint(stderr(), "listen: listen error on '%s': %r\n", addr);
			listench <-= nc;
			exit;
		}
		if (verbose)
			sys->fprint(stderr(), "listen: got connection on %s from %s",
					addr, readfile(nc.dir + "/remote"));
		nc.dfd = sys->open(nc.dir + "/data", Sys->ORDWR);
		if (nc.dfd == nil)
			sys->fprint(stderr(), "listen: cannot open %s: %r\n", nc.dir + "/data");
		else{
			if(nc.cfd != nil)
				sys->fprint(nc.cfd, "keepalive");
			listench <-= nc;
		}
	}
}

authenticator(authch: chan of (string, ref Dial->Connection),
		c: ref Dial->Connection, algs: list of string, addr: string)
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
