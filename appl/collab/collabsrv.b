implement Collabsrv;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
include "security.m";
	auth: Auth;

include "srvmgr.m";
include "proxy.m";

include "arg.m";

Collabsrv: module
{
	init: fn (ctxt: ref Draw->Context, args: list of string);
};

authinfo: ref Keyring->Authinfo;

stderr: ref Sys->FD;
Srvreq, Srvreply: import Srvmgr;

usage()
{
	sys->fprint(stderr, "usage: collabsrv [-k keyfile] [-n netaddress] [dir]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	(err, user) := user();
	if (err != nil)
		error(err);

	netaddr := "tcp!*!9999";
	keyfile := "/usr/" + user + "/keyring/default";
	root := "/services/collab";

	arg := load Arg Arg->PATH;
	arg->init(args);
	while ((opt := arg->opt()) != 0)
		case opt {
		'k' =>
			keyfile = arg->arg();
			if (keyfile == nil)
				usage();
			if (keyfile[0] != '/' && (len keyfile < 2 || keyfile[0:2] != "./"))
				keyfile = "/usr/" + user + "/keyring/" + keyfile;
		'n' =>
			netaddr = arg->arg();
			if (netaddr == nil)
				usage();
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;
	if(args != nil)
		root = hd args;

	auth = load Auth Auth->PATH;
	if (auth == nil)
		badmodule(Auth->PATH);

	kr := load Keyring Keyring->PATH;
	if (kr == nil)
		badmodule(Keyring->PATH);
	
	srvmgr := load Srvmgr Srvmgr->PATH;
	if (srvmgr == nil)
		badmodule(Srvmgr->PATH);

	err = auth->init();
	if (err != nil)
		error(sys->sprint("failed to init Auth: %s", err));

	authinfo = kr->readauthinfo(keyfile);
	kr = nil;
	if (authinfo == nil)
		error(sys->sprint("cannot read %s: %r", keyfile));

	netaddr = netmkaddr(netaddr, "tcp", "9999");
	(ok, c) := sys->announce(netaddr);
	if (ok < 0)
		error(sys->sprint("cannot announce %s: %r", netaddr));

	rc: chan of ref Srvreq;
	(err, rc) = srvmgr->init(root);
	if (err != nil)
		error(err);

	sys->print("Srvmgr started\n");

	for (;;) {
		(okl, nc) := sys->listen(c);
		if (okl < 0) {
			sys->print("listen failed: %r\n");
			sys->sleep(1000);
			return;
		}
		fd := sys->open(nc.dir+"/data", Sys->ORDWR);
		if(nc.cfd != nil)
			sys->fprint(nc.cfd, "keepalive");
		nc.cfd = nil;
		if (fd != nil)
			spawn newclient(rc, fd, root);
		fd = nil;
	}
}

badmodule(path: string)
{
	error(sys->sprint("cannot load module %s: %r", path));
}

error(s: string)
{
	sys->fprint(stderr, "collabsrv: %s\n", s);
	raise "fail:error";
}

user(): (string, string)
{
	sys = load Sys Sys->PATH;
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return (sys->sprint("can't open /dev/user: %r"), nil);
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return (sys->sprint("failed to read /dev/user: %r"), nil);
	return (nil, string buf[0:n]);	
}

newclient(rc: chan of ref Srvreq, fd: ref Sys->FD, root: string)
{
	algs := "none" :: "clear" :: "md4" :: "md5" :: nil;
	sys->print("new client\n");
	proxy := load Proxy Proxy->PATH;
	if (proxy == nil) {
		sys->fprint(stderr, "collabsrv: cannot load %s: %r\n", Proxy->PATH);
		return;
	}
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS|Sys->FORKENV, nil);
	s := "";
	(fd, s) = auth->server(algs, authinfo, fd, 1);
	if (fd == nil){
		sys->fprint(stderr, "collabsrv: cannot authenticate: %s\n", s);
		return;
	}
	sys->fprint(stderr, "uname: %s\n", s);
	spawn proxy->init(root, fd, rc, s);
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, l) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}
