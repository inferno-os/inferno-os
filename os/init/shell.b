implement InitShell;

include "sys.m";
include "draw.m";

sys: Sys;

InitShell: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Sh: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	shell := load Sh "/dis/sh.dis";

	sys = load Sys Sys->PATH;

	if(sys != nil)
		sys->print("init: starting shell\n");

#	sys->bind("#I", "/net", sys->MAFTER);	# IP
	sys->bind("#p", "/prog", sys->MREPL);	# prog device
	sys->bind("#d", "/fd", Sys->MREPL);
	sys->bind("#i", "/dev", sys->MREPL); 	# draw device
	sys->bind("#t", "/dev", sys->MAFTER);	# serial line
	sys->bind("#c", "/dev", sys->MAFTER); 	# console device
	sys->bind("#W","/dev",sys->MAFTER);	# Flash
#	sys->bind("#O", "/dev", sys->MAFTER);	# Modem
#	sys->bind("#T","/dev",sys->MAFTER);	# Touchscreen

	srv();

	spawn shell->init(nil, nil);
}

srv()
{
	remotedebug := sysenv("remotedebug");
	if(remotedebug != "1")
		return;

	sys->print("srv...");
	if(echoto("#t/eia0ctl", "b38400") < 0)
		return;

	fd := sys->open("/dev/eia0", Sys->ORDWR);
	if (fd == nil) {
		sys->print("eia data open: %r\n");
		return;
	}
	if (sys->export(fd, "/", Sys->EXPASYNC) < 0) {
		sys->print("export: %r\n");
		return;
	}
	sys->print("ok\n");
}

sysenv(param: string): string
{
	fd := sys->open("#c/sysenv", sys->OREAD);
	if (fd == nil)
		return(nil);
	buf := array[4096] of byte;
	nb := sys->read(fd, buf, len buf);
	(nfl,fl) := sys->tokenize(string buf, "\n");
	while (fl != nil) {
		pair := hd fl;
		(npl, pl) := sys->tokenize(pair, "=");
		if (npl > 1) {
			if ((hd pl) == param)
				return hd tl pl;
		}
		fl = tl fl;
	}
	return nil ;
}

echoto(fname, str: string): int
{
	fd := sys->open(fname, Sys->OWRITE);
	if(fd == nil) {
		sys->print("%s: %r\n", fname);
		return -1;
	}
	x := array of byte str;
	if(sys->write(fd, x, len x) == -1) {
		sys->print("write: %r\n");
		return -1;
	}
	return 0;
}
