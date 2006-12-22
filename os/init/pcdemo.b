#
#	Init shell ``with the kitchen sink'', for development purposes.
#
implement InitShell;

include "sys.m";
include "draw.m";

sys: Sys;
FD, Connection, sprint, Dir: import sys;
print, fprint, open, bind, mount, dial, sleep, read: import sys;

stderr:	ref sys->FD;						# standard error FD

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
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	sys->print("Welcome to Inferno...\n");

	sys->pctl(Sys->NEWNS, nil);
	if (imount("/n/remote")) {
		bind("/n/remote", "/", sys->MAFTER);
		bind("/n/remote/dis", "/dis", sys->MBEFORE);
		mountkfs("#W/flash0fs", "fs", "/n/local", sys->MREPL);
	}
	else {
		# bind("#U/pcdemo", "/", sys->MREPL);
		# mountkfs("#U/pcdemo.kfs", "fs", "/", sys->MBEFORE);
		# bind("#U/pcdemo/usr", "/usr", sys->MAFTER);
		mountkfs("#R/ramdisk", "fs", "/", sys->MBEFORE);
		bind("/services", "/data", sys->MREPL|sys->MCREATE);
	}

	namespace();
	srv();

	if (1) {
		bind("/icons/oldlogon.bit", "/icons/logon.bit", sys->MREPL);
		bind("/icons/tk/oldinferno.bit", "/icons/tk/inferno.bit", sys->MREPL);
	}

	sys->print("starting shell (type wm/logon or wm/wmcp)\n");
	shell := sysenv("shell");
	if (shell == nil)
		shell = "/dis/sh.dis";
	sh := load Sh shell;
	spawn sh->init(nil, nil);
}

namespace()
{
	# Bind anything useful we can get our hands on.  Ignore errors.
	sys->print("namespace...\n");
	sys->bind("#I", "/net", sys->MAFTER);	# IP
	sys->bind("#I1", "/net.alt", sys->MREPL);	# second IP for PPP tests
	sys->bind("#p", "/prog", sys->MREPL);	# prog device
	sys->bind("#d", "/fd", Sys->MREPL);
	sys->bind("#i", "/dev", sys->MREPL); 	# draw device
	sys->bind("#t", "/dev", sys->MAFTER);	# serial line
	sys->bind("#c", "/dev", sys->MAFTER); 	# console device
	sys->bind("#W", "/dev", sys->MAFTER);	# Flash
	sys->bind("#O", "/dev", sys->MAFTER);	# Modem
	sys->bind("#T", "/dev", sys->MAFTER);	# Touchscreen
	sys->bind("#H", "/dev", sys->MAFTER);	# Ata disk device
	sys->bind("#b", "/dev", sys->MAFTER);	# debug device
	sys->bind("#c", "/chan", sys->MREPL);
	sys->bind("/data", "/usr/inferno", sys->MREPL|sys->MCREATE);
	sys->bind("/data", "/usr/charon", sys->MREPL|sys->MCREATE);
	sys->bind("/data", "/usr/shaggy", sys->MREPL|sys->MCREATE);
}

mountkfs(devname: string, fsname: string, where: string, flags: int): int
{
	sys->print("mount kfs...\n");
	fd := sys->open("#Kcons/kfsctl", sys->OWRITE);
	if (fd == nil) {
		sys->fprint(stderr, "could not open #Kcons/kfsctl: %r\n");
		return 0;
	}
	kfsopt := "";
	kfsrw := sysenv("kfsrw");
#	if (kfsrw != "1")
#		kfsopt = " ronly";
	b := array of byte ("filsys " + fsname + " " + devname + kfsopt);
	if (sys->write(fd, b, len b) < 0) {
		sys->fprint(stderr, "could not write #Kcons/kfsctl: %r\n");
		return 0;
	}
	if (sys->bind("#K" + fsname, where, flags) < 0) {
		sys->fprint(stderr, "could not bind %s to %s: %r\n", "#K" + fsname, where);
		return 0;
	}
	return 1;
}

dialfs(server: string, where: string): int
{
	ok, n: int;
	c: Connection;

	(ok, c) = dial("tcp!" + server + "!6666", nil);
	if(ok < 0)
		return 0;

	sys->print("mount...");

	c.cfd = nil;
	n = mount(c.dfd, where, sys->MREPL, "");
	if(n > 0)
		return 1;
	sys->print("mount failed: %r\n");
	return 0;
}

Bootpreadlen: con 128;

imount(where: string): int
{
	sys->print("bootp...");
	if (sys->bind("#I", "/net", sys->MREPL) < 0) {
		sys->fprint(stderr, "could not bind ip device: %r\n");
		return 0;
	}
	if (sys->bind("#l", "/net", sys->MAFTER) < 0) {
		sys->fprint(stderr, "could not bind ether device: %r\n");
		return 0;
	}

	fd := sys->open("/net/ipifc/clone", sys->OWRITE);
	if(fd == nil) {
		sys->print("init: open /net/ipifc: %r");
		return 0;
	}

	cfg := array of byte "bind ether ether0";
	if(sys->write(fd, cfg, len cfg) != len cfg) {
		sys->fprint(stderr, "could not bind interface: %r\n");
		return 0;
	}
	cfg = array of byte "bootp";
	if(sys->write(fd, cfg, len cfg) != len cfg) {
		sys->fprint(stderr, "could not bootp: %r\n");
		return 0;
	}

	bfd := sys->open("/net/bootp", sys->OREAD);
	if(bfd == nil) {
		sys->print("init: can't open /net/bootp: %r");
		return 0;
	}

	buf := array[Bootpreadlen] of byte;
	nr := sys->read(bfd, buf, len buf);
	bfd = nil;
	if(nr <= 0) {
		sys->print("init: read /net/bootp: %r");
		return 0;
	}

	(ntok, ls) := sys->tokenize(string buf, " \t\n");
	while(ls != nil) {
		if(hd ls == "fsip"){
			ls = tl ls;
			break;
		}
		ls = tl ls;
	}
	if(ls == nil) {
		sys->print("init: server address not in bootp read");
		return 0;
	}

	server := hd ls;
	sys->print("imount: server %s\n", server);

	return dialfs(server, where);
}

srv()
{
	remotedebug := sysenv("remotedebug");
	if(remotedebug != "1")
		return;
	remotespeed := sysenv("remotespeed");
	if (remotespeed == nil)
		remotespeed = "38400";

	sys->print("srv...");
	if(echoto("#t/eia0ctl", "b" + remotespeed) < 0)
		return;

	fd := sys->open("/dev/eia0", Sys->ORDWR);
	if (fd == nil) {
		sys->print("eia data open: %r\n");
		return;
	}
	if (sys->export(fd, Sys->EXPASYNC) < 0) {
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
	return nil;
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

hang()
{
	c := chan of int;
	<- c;
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
