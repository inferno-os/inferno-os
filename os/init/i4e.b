implement Init;

#
# init program for Inferno 4thEd demo box
#

include "sys.m";
	sys: Sys;
	FD, Connection, Dir: import sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "security.m";
	auth:	Auth;

include "dhcp.m";
	dhcpclient: Dhcpclient;
	Bootconf: import dhcpclient;

I4EBOOT: con "/lib/boot.sh";

Init: module
{
	init:	fn();
};

Command: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Bootpreadlen: con 128;

init()
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if(auth != nil)
		auth->init();

	sys->print("**\n** Inferno\n** Vita Nuova\n**\n");

	sys->print("Setup boot net services ...\n");
	
	#
	# Setup what we need to call a server and
	# Authenticate
	#
	dobind("#l", "/net", Sys->MREPL);
	dobind("#I", "/net", Sys->MAFTER);
	dobind("#c", "/dev", Sys->MAFTER);


	fd := sys->open("/net/ipifc/clone", sys->OWRITE);
	if(fd == nil)
		fail(sys->sprint("iopen /net/ipifc/clone: %r"));

	if(sys->fprint(fd, "bind ether /net/ether0") < 0)
		fail(sys->sprint("could not bind interface: %r"));

	fsip: string;

	dhcpclient = load Dhcpclient Dhcpclient->PATH;
	if(dhcpclient == nil)
		fail(sys->sprint("can't load dhcpclient: %r"));

	sys->print("dhcp...");
	dhcpclient->init();
	(cfg, nil, e) := dhcpclient->dhcp("/net", fd, "/net/ether0/addr", nil, nil);
	if(e != nil)
		fail(sys->sprint("dhcp: %s", e));
	fsip = cfg.getip(Dhcpclient->OP9fs);
	if(fsip == nil)
		fail("server address not in bootp/dhcp reply");
	dhcpclient = nil;

	infd := sys->open("/dev/cons", Sys->OREAD);
	if(infd == nil)
		sys->print("warning: no kbd\n");

	err := rootfs(fsip);
	if(err != nil)
		fail(err);

	#
	# default namespace
	#
	dobind("#c", "/dev", Sys->MREPL);			# console
	dobind("#p", "/prog", Sys->MREPL);		# prog device
	sys->bind("#d", "/fd", Sys->MREPL);
	sys->pctl(Sys->NEWENV, nil);
	dobind("#e", "/env", Sys->MREPL|Sys->MCREATE);	# env device

	sys->print("clock...\n");
	setclock();

	sys->print("boot...\n");
	sys->pctl(Sys->NEWFD, 0::1::2::nil);
	done := chan of string;
	spawn boot(done);
	err = <- done;
	if(err != nil)
		fail("boot script failed: "+err);
	fail("boot script exit");
}

rootfs(server: string): string
{
	ok: int;
	c: Connection;

	sys->print("readauthinfo...\n");
	ai := kr->readauthinfo("/keydb/mutual");
	if(ai == nil)
		return sys->sprint("readauthinfo /keydb/mutual failed: %r");

	addr := "tcp!" + server + "!9999";
	for(gap := 3;; gap *= 2){
		sys->print("Connect (%s)...", addr);
		(ok, c) = sys->dial(addr, nil);
		if(ok != -1)
			break;
		sys->print("failed: %r\n");
		if(gap > 60)
			gap = 60;
		sys->sleep(gap*1000);
	}

	sys->print("\nConnected ...");
	if(kr != nil && auth != nil){
		err: string;
		sys->print("Authenticate ...");
		(c.dfd, err) = auth->client("none", ai, c.dfd);
		if(c.dfd == nil)
			return sys->sprint("authentication failed: %s", err);
	}
	sys->print("mount ...");

	c.cfd = nil;
	sys->pctl(Sys->NEWNS, nil);
	if(sys->mount(c.dfd, nil, "/", sys->MREPL, "") < 0)	# TO DO: would be better to mount behind
		return sys->sprint("mount failed: %r");
	sys->chdir("/");
	return nil;
}

boot(done: chan of string)
{
	{
		shell := load Command "/dis/sh.dis";
		if(shell == nil){
			done <-= sys->sprint("load /dis/sh.dis: %r");
			exit;
		}
		shell->init(nil, "/dis/sh.dis"::I4EBOOT::nil);
	} exception e {
	"*" =>
		done <-= e;
		exit;
	}
	done <-= nil;
}

setclock()
{
	(ok, dir) := sys->stat("/");
	if(ok < 0){
		sys->print("stat /: %r");
		return;
	}

	fd := sys->open("/dev/time", sys->OWRITE);
	if(fd == nil){
		sys->print("open /dev/time: %r");
		return;
	}

	# Time is kept as microsecs, atime is in secs
	b := array of byte sys->sprint("%d000000", dir.atime);
	if(sys->write(fd, b, len b) != len b)
		sys->print("write /dev/time: %r");
}

#
# Bind wrapper which reports errors
#

dobind(f, t: string, flags: int)
{
	if(sys->bind(f, t, flags) < 0)
		sys->print("bind(%s, %s, %d) failed: %r\n", f, t, flags);
}

fail(msg: string)
{
	sys->print("%s\n", msg);
	sys->bind("/", "#//n/remote", Sys->MREPL);
	sys->bind("#//", "/", Sys->MREPL);
	shell := load Command "#//dis/sh.dis";
	if(shell == nil){
		sys->print("cannot load shell: %r\n");
		exit;
	}
	shell->init(nil, "/dis/sh.dis"::"-i"::nil);
	exit;
}
