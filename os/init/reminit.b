implement Init;
#
# init program for standalone remote pc kernel - for benchmarking
#
include "sys.m";
sys: Sys;
FD, Connection, sprint, Dir: import sys;
print, fprint, open, bind, mount, dial, sleep, read, chdir: import sys;

include "draw.m";
draw: Draw;
Context: import draw;

include "keyring.m";
kr: Keyring;

include "security.m";
auth: Auth;

Init: module
{
	init:	fn();
};

Shell: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

remotefs(server: string): int
{
	ok, n: int;
	c: Connection;

	(ok, c) = dial("tcp!" + server + "!6666", nil);
	if(ok < 0)
		return -1;

	sys->print("Connected ...\n");
	if(kr != nil){
		err: string;
		sys->print("Authenticate ...");
		ai := kr->readauthinfo("/nvfs/default");
		if(ai == nil){
			sys->print("readauthinfo /nvfs/default failed: %r\n");
			sys->print("trying mount as `nobody'\n");
		}
		(c.dfd, err) = auth->client("none", ai, c.dfd);
		if(c.dfd == nil){
			sys->print("authentication failed: %s\n", err);
			return -1;
		}
	}

	sys->print("mount ...\n");

	c.cfd = nil;
	n = mount(c.dfd, "/n/remote", sys->MREPL, "");
	if(n > 0)
		return 0;
	return -1;
}

Bootpreadlen: con 128;

bootp(): string
{
#
#	BUG: if bootp fails, can't then use "add ether" correctly
#
	fd := open("/net/ipifc", sys->OWRITE);
	if(fd == nil) {
		print("init: open /net/ipifc: %r");
		return nil;
	}
	fprint(fd, "bootp /net/ether0");

	fd = open("/net/bootp", sys->OREAD);
	if(fd == nil) {
		print("init: open /net/bootp: %r\n");
		return nil;
	}

	buf := array[Bootpreadlen] of byte;
	nr := read(fd, buf, len buf);
	fd = nil;
	if(nr > 0) {
		(ntok, ls) := sys->tokenize(string buf, " \t\n");
		while(ls != nil) {
			if(hd ls == "fsip") {
				ls = tl ls;
				break;
			}
			ls = tl ls;
		}
		srv : string;
		if(ls == nil || ((srv = hd ls) == "0.0.0.0")) {
			print("init: server address not in bootp read\n");
			return nil;
		}
		return srv;
	}
	return nil;
}

init()
{

	sys = load Sys Sys->PATH;
	stdin := sys->fildes(0);
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
	sys->print("Bind ethernet ...\n");
	bind("#l", "/net", sys->MREPL);
	sys->print("Bind IP ...\n");
	bind("#I", "/net", sys->MAFTER);
	sys->print("Bind console ...\n");
	bind("#c", "/dev", sys->MAFTER);

	setsysname();
	if (1) {
		print("bootp ...\n");
		srv := bootp();
		if (srv != nil)
			if (remotefs(srv) < 0)
				print("No remote filesystem\n");
			else {
				print("Remote filesystem mounted\n");
				bind("/n/remote/dis", "/dis", sys->MBEFORE);
				bind("/n/remote/dis/lib", "/dis/lib", sys->MBEFORE);
			}
	} else {
		print("Standalone mode\n");
		fd := open("/net/ipifc", sys->OWRITE);
		if(fd == nil) {
			print("init: open /net/ipifc: %r");
			exit;
		}
		fprint(fd, "add ether /net/ether0 %s %s", "200.1.1.60", "255.255.255.0");
		fd = nil;
	}
	#
	# default namespace
	#
	sys->unmount(nil, "/dev");
	bind("#c", "/dev", sys->MBEFORE);			# console
	bind("#l", "/net", sys->MBEFORE);		# ethernet
	bind("#I", "/net", sys->MBEFORE);		# TCP/IP
	bind("#p", "/prog", sys->MREPL);		# prog device
	sys->bind("#d", "/fd", Sys->MREPL);

	bind("#T", "/dev", sys->MBEFORE);		# kprof device
	bind("#x", "/dev", sys->MBEFORE);		# bench device

	print("clock...\n");
	setclock();

	print("Server...\n");
	dc: ref Context;
	cs := load Shell "/dis/ndb/cs.dis";
	if(cs == nil)
		print("Server not loaded\n");
	else
		cs->init(dc, "cs" :: nil);
	server := load Shell "/dis/lib/srv.dis";
	if(server == nil)
		print("Server not loaded\n");
	else {
#		server->init(dc, "srv" :: nil);
	}

	print("Console...\n");
sys->chdir("/n/remote/usr/john/appl/bench");
	shell := load Shell "/dis/sh.dis";
	if(shell == nil) {
		print("init: load /dis/sh.dis: %r");
		exit;
	}
	shell->init(dc, nil);
}

setclock()
{
	(ok, dir) := sys->stat("/");
	if (ok < 0) {
		print("init: stat /: %r");
		return;
	}

	fd := sys->open("/dev/time", sys->OWRITE);
	if (fd == nil) {
		print("init: open /dev/time: %r");
		return;
	}

	# Time is kept as microsecs, atime is in secs
	b := array of byte sprint("%d000000", dir.atime);
	if (sys->write(fd, b, len b) != len b)
		print("init: write /dev/time: %r");
}

#
# Set system name from nvram
#
setsysname()
{
	fd := open("/nvfs/ID", sys->OREAD);
	if(fd == nil)
		return;
	fds := open("/dev/sysname", sys->OWRITE);
	if(fds == nil)
		return;
	buf := array[128] of byte;
	nr := sys->read(fd, buf, len buf);
	if(nr <= 0)
		return;
	sys->write(fds, buf, nr);
}

readline(fd: ref Sys->FD): string
{
	l := array [128] of byte;
	nb := sys->read(fd, l, len l);
	if(nb <= 1)
		return "";
	return string l[0:nb-1];
}

