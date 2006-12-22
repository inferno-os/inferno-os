implement Init;
#
# init program for Motorola 800 series (serial console only)
#
include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

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
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Bootpreadlen: con 128;

# option switches
UseLocalFS: con 1<<0;
EtherBoot: con 1<<1;
Prompting: con 1<<3;

lfs(): int
{
	if(!ftlinit("#F/flash/flash", 1024*1024, 1024*1024))
		return -1;
	if(mountkfs("#X/ftldata", "main", "flash") < 0)
		return -1;
	if(sys->bind("#Kmain", "/n/local", sys->MREPL) < 0){
		sys->print("can't bind #Kmain to /n/local: %r\n");
		return -1;
	}
	if(sys->bind("/n/local", "/", Sys->MCREATE|Sys->MREPL) < 0){
		sys->print("can't bind /n/local after /: %r\n");
		return -1;
	}
	return 0;
}

donebind := 0;

#
# set up network mount
#
netfs(mountpt: string): int
{
	sys->print("bootp ...");

	fd: ref Sys->FD;
	if(!donebind){
		fd = sys->open("/net/ipifc/clone", sys->OWRITE);
		if(fd == nil) {
			sys->print("init: open /net/ipifc/clone: %r\n");
			return -1;
		}
		if(sys->fprint(fd, "bind ether %s", "/net/ether0") < 0) {
			sys->print("could not bind ether0 interface: %r\n");
			return -1;
		}
		donebind = 1;
	}else{
		fd = sys->open("/net/ipifc/0/ctl", Sys->OWRITE);
		if(fd == nil){
			sys->print("init: can't reopen /net/ipifc/0/ctl: %r\n");
			return -1;
		}
	}
	if(sys->fprint(fd, "bootp") < 0){
		sys->print("init: bootp failed: %r\n");
		return -1;
	}

	server := bootp();
	if(server == nil)
		return -1;

	net := "tcp";	# how to specify il?
	svcname := net + "!" + server + "!6666";

	sys->print("dial %s...", svcname);

	(ok, c) := sys->dial(svcname, nil);
	if(ok < 0){
		sys->print("can't dial %s: %r\n", svcname);
		return -1;
	}

	sys->print("\nConnected ...\n");
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

	sys->print("mount %s...", mountpt);

	c.cfd = nil;
	n := sys->mount(c.dfd, nil, mountpt, sys->MREPL, "");
	if(n > 0)
		return 0;
	if(n < 0)
		sys->print("%r");
	return -1;
}

init()
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if(auth != nil)
		auth->init();

	sys->print("**\n** Inferno\n** Vita Nuova\n**\n");

	optsw := options();
	sys->print("Switch options: 0x%ux\n", optsw);

	#
	# Setup what we need to call a server and
	# Authenticate
	#
	sys->bind("#l", "/net", sys->MREPL);
	sys->bind("#I", "/net", sys->MAFTER);
	sys->bind("#c", "/dev", sys->MAFTER);

	fsready := 0;
	mountpt := "/";
	usertc := 0;

	if((optsw & Prompting) == 0){
		if(optsw & UseLocalFS){
			sys->print("Option: use local file system\n");
			if(lfs() == 0){
				fsready = 1;
				mountpt = "/n/remote";
			}
		}

		if(optsw & EtherBoot){
			sys->print("Attempting remote mount\n");
			if(netfs(mountpt) == 0)
				fsready = 1;
		}
	}

	if(fsready == 0){

		sys->print("\n\n");

		stdin := sys->fildes(0);
		buf := array[128] of byte;
		sources := "fs" :: "net" :: nil;

		loop: for(;;) {
			sys->print("root from (");
			cm := "";
			for(l := sources; l != nil; l = tl l){
				sys->print("%s%s", cm, hd l);
				cm = ",";
			}
			sys->print(")[%s] ", hd sources);

			n := sys->read(stdin, buf, len buf);
			if(n <= 0)
				continue;
			if(buf[n-1] == byte '\n')
				n--;

			(nil, choice) := sys->tokenize(string buf[0:n], "\t ");

			if(choice == nil)
				choice = sources;
			opt := hd choice;
			case opt {
			* =>
				sys->print("\ninvalid boot option: '%s'\n", opt);
				break;
			"fs" or "" =>
				if(lfs() == 0){
					usertc = 1;
					break loop;
				}
			"net" =>
				if(netfs("/") == 0)
					break loop;
			}
		}
	}

	#
	# default namespace
	#
	sys->unmount(nil, "/dev");
	sys->bind("#c", "/dev", sys->MBEFORE);			# console
	sys->bind("#l", "/net", sys->MBEFORE);		# ethernet
	sys->bind("#I", "/net", sys->MBEFORE);		# TCP/IP
	sys->bind("#p", "/prog", sys->MREPL);		# prog device
	sys->bind("#d", "/fd", Sys->MREPL);

	setsysname();

	sys->print("clock...\n");
	setclock(usertc, mountpt);

	sys->print("Console...\n");

	shell := load Shell "/dis/sh.dis";
	if(shell == nil) {
		sys->print("init: load /dis/sh.dis: %r");
		exit;
	}
	dc: ref Draw->Context;
	shell->init(dc, nil);
}

setclock(usertc: int, timedir: string)
{
	now := 0;
	if(usertc){
		fd := sys->open("#r/rtc", Sys->OREAD);
		if(fd != nil){
			b := array[64] of byte;
			n := sys->read(fd, b, len b-1);
			if(n > 0){
				b[n] = byte 0;
				now = int string b;
				if(now <= 16r20000000)
					now = 0;	# rtc itself is not initialised
			}
		}
	}
	if(now == 0){
		(ok, dir) := sys->stat(timedir);
		if (ok < 0) {
			sys->print("init: stat %s: %r", timedir);
			return;
		}
		now = dir.atime;
	}
	fd := sys->open("/dev/time", sys->OWRITE);
	if (fd == nil) {
		sys->print("init: can't open /dev/time: %r");
		return;
	}

	# Time is kept as microsecs, atime is in secs
	b := array of byte sys->sprint("%ud000000", now);
	if (sys->write(fd, b, len b) != len b)
		sys->print("init: can't write /dev/time: %r");
}

#
# Set system name from nvram
#
setsysname()
{
	fd := sys->open("/nvfs/ID", sys->OREAD);
	if(fd == nil)
		return;
	fds := sys->open("/dev/sysname", sys->OWRITE);
	if(fds == nil)
		return;
	buf := array[128] of byte;
	nr := sys->read(fd, buf, len buf);
	if(nr <= 0)
		return;
	sys->write(fds, buf, nr);
}

#
# fetch options from switch DS2
#
options(): int
{
	fd := sys->open("#r/switch", Sys->OREAD);
	if(fd == nil){
		sys->print("can't open #r/switch: %r\n");
		return 0;
	}
	b := array[20] of byte;
	n := sys->read(fd, b, len b);
	s := string b[0:n];
	return int s;
}

bootp(): string
{
	fd := sys->open("/net/bootp", sys->OREAD);
	if(fd == nil) {
		sys->print("init: can't open /net/bootp: %r");
		return nil;
	}

	buf := array[Bootpreadlen] of byte;
	nr := sys->read(fd, buf, len buf);
	fd = nil;
	if(nr <= 0) {
		sys->print("init: read /net/bootp: %r");
		return nil;
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
		return nil;
	}

	srv := hd ls;

	sys->print("%s\n", srv);

	return srv;
}

#
# set up flash translation layer
#
ftldone := 0;

ftlinit(flashmem: string, offset: int, length: int): int
{
	if(ftldone)
		return 1;
	sys->print("Set flash translation of %s at offset %d (%d bytes)\n", flashmem, offset, length);
	fd := sys->open("#X/ftlctl", Sys->OWRITE);
	if(fd == nil){
		sys->print("can't open #X/ftlctl: %r\n");
		return 0;
	}
	if(sys->fprint(fd, "init %s %ud %ud", flashmem, offset, length) <= 0){
		sys->print("can't init flash translation: %r");
		return 0;
	}
	ftldone = 1;
	return 1;
}

#
# Mount kfs filesystem
#
mountkfs(devname: string, fsname: string, options: string): int
{
	fd := sys->open("#Kcons/kfsctl", sys->OWRITE);
	if(fd == nil) {
		sys->print("could not open #Kcons/kfsctl: %r\n");
		return -1;
	}
	if(sys->fprint(fd, "filsys %s %s %s", fsname, devname, options) <= 0){
		sys->print("could not write #Kcons/kfsctl: %r\n");
		return -1;
	}
	if(options == "ro")
		sys->fprint(fd, "cons flashwrite");
	return 0;
}
