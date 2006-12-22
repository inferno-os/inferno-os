implement Init;

#
# ARM evaluator 7t
#

include "sys.m";
sys: Sys;
FD, Connection, sprint, Dir: import sys;
print, fprint, open, bind, mount, dial, sleep, read: import sys;

include "draw.m";
include "sh.m";
draw: Draw;
Context: import draw;

Init: module
{
	init:	fn();
};

Logon: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

Bootpreadlen: con 128;

init()
{
	sys = load Sys Sys->PATH;
#	kr = load Keyring Keyring->PATH;
#	auth = load Auth Auth->PATH;
#	if(auth != nil)
#		auth->init();
	
	sys->print("**\n** Inferno\n** Vita Nuova\n**\n");

#	sys->print("Setup boot net services ...\n");
	
	#
	# Setup what we need to call a server and
	# Authenticate
	#
#	bind("#l", "/net", sys->MREPL);
#	bind("#I", "/net", sys->MAFTER);
	bind("#c", "/dev", sys->MAFTER);
	bind("#r", "/dev", sys->MAFTER);
#	nvramfd := sys->open("#r/nvram", sys->ORDWR);
#	if(nvramfd != nil){
#		spec = "#Fnvram";
#		if(bind(spec, "/nvfs", sys->MAFTER) < 0)
#			print("init: bind %s: %r\n", spec);
#	}

#	setsysname();

	#
	# default namespace
	#
	bind("#c", "/dev", sys->MREPL);			# console
	bind("#t", "/dev", sys->MAFTER);		# serial port
	bind("#r", "/dev", sys->MAFTER);		# RTC
#	if(spec != nil)
#		bind(spec, "/nvfs", sys->MBEFORE|sys->MCREATE);	# our keys
#	bind("#l", "/net", sys->MBEFORE);		# ethernet
#	bind("#I", "/net", sys->MBEFORE);		# TCP/IP
	bind("#p", "/prog", sys->MREPL);		# prog device
	sys->bind("#d", "/fd", Sys->MREPL);

	sys->print("clock...\n");
	setclock();

	sys->print("logon...\n");

#	sys->chdir("/usr/inferno"); 
#	logon := load Logon "/dis/sh.dis";
#	spawn logon->init(dc, nil);
	ts := load Sh "/dis/sh.dis";
	ts->init(nil, nil);
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
