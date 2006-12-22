implement Init;
#
# init program for native inferno, generic pc version
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

Init: module
{
	init:	fn();
};

Shell: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

init()
{

	sys = load Sys Sys->PATH;
	stdin := sys->fildes(0);
	kr = load Keyring Keyring->PATH;

	sys->print("**\n** Inferno\n** Vita Nuova\n**\n");

	sys->print("Setup boot net services ...\n");

	#
	# Setup what we need to call a server and
	# Authenticate
	#
	sys->print("Bind console ...\n");
	bind("#c", "/dev", sys->MAFTER);

	setsysname();
	print("Standalone mode\n");
	#
	# default namespace
	#
	sys->unmount(nil, "/dev");
	bind("#p", "/prog", sys->MREPL);		# prog device
	sys->bind("#d", "/fd", Sys->MREPL);
	bind("#c", "/dev", sys->MBEFORE);		# console
	bind("#m", "/dev", sys->MAFTER);		# mouse setup device
	bind("#t", "/dev", sys->MAFTER);		# serial device

	mouse := load Shell "/dis/mouse.dis";
	if (mouse != nil) {
		print("Setting up mouse\n");
		mouse->init(nil, "/dis/mouse.dis" :: nil);
		mouse = nil;
	}

	# create fake nameserver db that can be written to later
	ramfile := load Shell "/dis/ramfile.dis";
	if (ramfile != nil) {
		ramfile->init(nil, "/dis/ramfile.dis" :: "/services/dns/db" :: "" :: nil);
		ramfile = nil;
	}

	print("Console...\n");
	shell := load Shell "/dis/sh.dis";
	if(shell == nil) {
		print("init: load /dis/sh.dis: %r\n");
		exit;
	}
	print("starting shell\n");
	shell->init(nil, "/dis/sh.dis" :: nil);
	print("shell exited, bye bye\n");
}


#
# Set system name from nvram
#
setsysname()
{
	fds := open("/dev/sysname", sys->OWRITE);
	if(fds == nil)
		return;
	buf := array of byte "genericpc";
	sys->write(fds, buf, len buf);
}
