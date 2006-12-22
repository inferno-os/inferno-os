implement Connect;

include "sys.m";
	sys: Sys;

include "draw.m";
include "keyring.m";
include "security.m";
include "arg.m";

Connect: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

remotedir := "/n/remote";
localdir := "/n/ftree/collab";
COLLABPORT: con "9999";	# TO DO: needs symbolic name in services

usage()
{
	sys->fprint(sys->fildes(2), "Usage: connect [-v] [-C cryptoalg] [-k keyring] [net!addr [localdir]]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	vflag := 0;
	alg := "none";
	keyfile := "";
	netaddr := "$collab";

	arg := load Arg Arg->PATH;
	if(arg != nil){
		arg->init(args);
		while((c := arg->opt()) != 0)
			case c {
			'C' =>
				alg = arg->arg();
			'k' =>
				keyfile = arg->arg();
			'v' =>
				vflag++;
			* =>
				usage();
			}
	}
	args = arg->argv();
	arg = nil;

	if(args != nil){
		netaddr = hd args;
		args = tl args;
		if(args != nil)
			localdir = hd args;
	}

	if(vflag)
		sys->print("connect: dial %s\n", netaddr);
	(fd, user) := authdial(netaddr, keyfile, alg);
	if(vflag)
		sys->print("remote username is %s\n", user);
	if(sys->mount(fd, nil, remotedir, Sys->MREPL, nil) < 0)
		error(sys->sprint("can't mount %s on %s: %r", netaddr, remotedir));
	fd = nil;

	connectdir := remotedir+"/collab";
	if (sys->bind(connectdir, localdir, Sys->MCREATE|Sys->MREPL) < 0){
		error(sys->sprint("cannot bind %s onto %s: %r\n", connectdir, localdir));
		raise "fail:error";
	}

	# if something such as ftree is running and watching for changes, tell it about this one
	fd = sys->open("/chan/nsupdate", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "/n/ftree/collab");
	if(vflag)
		sys->print("collab connected\n");
}

authdial(addr, keyfile, alg: string): (ref Sys->FD, string)
{
	cert : string;

	kr := load Keyring Keyring->PATH;
	if(kr == nil)
		error(sys->sprint("cannot load %s: %r", Keyring->PATH));

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
	if (ai == nil)
		error(sys->sprint("cannot read authentication data from %s: %r", cert));

	au := load Auth Auth->PATH;
	if(au == nil)
		error(sys->sprint("cannot load %s: %r", Auth->PATH));
	err := au->init();
	if(err != nil)
		error(sys->sprint("cannot init Auth: %s", err));

	(ok, c) := sys->dial(netmkaddr(addr, "tcp", COLLABPORT), nil);
	if(ok < 0)
		error(sys->sprint("can't dial %s: %r", addr));
	(fd, id_or_err) := au->client(alg, ai, c.dfd);
	if(fd == nil)
		error(sys->sprint("authentication failed: %s", id_or_err));

	return (fd, id_or_err);
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

error(m: string)
{
	sys->fprint(sys->fildes(2), "connect: %s\n", m);
	raise "fail:error";
}
