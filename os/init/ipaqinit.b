#
# ipaq
#
# TO DO: read params from params flash
#

implement Init;

include "sys.m";
	sys:	Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "security.m";
	auth: Auth;

include "dhcp.m";
	dhcpclient: Dhcpclient;
	Bootconf: import dhcpclient;

include "keyboard.m";

include "sh.m";

Init: module
{
	init:	fn();
};

Bootpreadlen: con 128;

ethername := "ether0";

# standard Inferno flash partitions

flashparts := array[] of {
	# bootstrap at 0x0 to 0x40000, don't touch
	"add params 0x40000 0x80000",
	"add kernel 0x80000 0x140000",
	"add fs 0x140000 end",
};

#
# initialise flash translation
# mount flash file system
# add devices
# start a shell or window manager
#

init()
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if(auth != nil)
		auth->init();

	sys->bind("/", "/", Sys->MREPL);

	lightup();

	localok := 0;
	if(lfs() >= 0){
		# let's just take a closer look
		sys->bind("/n/local/nvfs", "/nvfs", Sys->MREPL|Sys->MCREATE);
		(rc, nil) := sys->stat("/n/local/dis/sh.dis");
		if(rc >= 0)
			localok = 1;
		else
			err("local file system unusable");
	}
	netok := sys->bind("#l", "/net", Sys->MREPL) >= 0;
	if(!netok){
		netok = sys->bind("#l1", "/net", Sys->MREPL) >= 0;
		if(netok)
			ethername = "ether1";
	}
	if(netok)
		configether();

	dobind("#I", "/net", sys->MAFTER);	# IP
	dobind("#p", "/prog", sys->MREPL);	# prog
	dobind("#c", "/dev", sys->MREPL); 	# console
	sys->bind("#d", "/fd", Sys->MREPL);
	dobind("#t", "/dev", sys->MAFTER);	# serial line
	dobind("#i", "/dev", sys->MAFTER); 	# draw
	dobind("#m", "/dev", Sys->MAFTER);	# pointer
	sys->bind("#e", "/env", sys->MREPL|sys->MCREATE);	# environment
	sys->bind("#A", "/dev", Sys->MAFTER);	# optional audio
	dobind("#T","/dev",sys->MAFTER);	# touch screen and other ipaq devices

	timefile: string;
	rootsource: string;
	cfd := sys->open("/dev/consctl", Sys->OWRITE);
	if(cfd != nil)
		sys->fprint(cfd, "rawon");
	for(;;){
		(rootsource, timefile) = askrootsource(localok, netok);
		if(rootsource == nil)
			break;	# internal
		(rc, nil) := sys->stat(rootsource+"/dis/sh.dis");
		if(rc < 0)
			err("%s has no shell");
		else if(sys->bind(rootsource, "/", Sys->MAFTER) < 0)
			sys->print("can't bind %s on /: %r\n", rootsource);
		else{
			sys->bind(rootsource+"/dis", "/dis", Sys->MBEFORE|Sys->MCREATE);
			break;
		}
	}
	cfd = nil;

	setsysname("ipaq");			# set system name

	now := getclock(timefile, rootsource);
	setclock("/dev/time", now);
	if(timefile != "#r/rtc")
		setclock("#r/rtc", now/big 1000000);

	sys->chdir("/");
	if(netok){
		start("ndb/dns", nil);
		start("ndb/cs", nil);
	}
	calibrate();
	startup := "/nvfs/startup";
	if(sys->open(startup, Sys->OREAD) != nil){
		shell := load Command Sh->PATH;
		if(shell != nil){
			sys->print("Running %s\n", startup);
			shell->init(nil, "sh" :: startup :: nil);
		}
	}
	user := rdenv("user", "inferno");
	(ok, nil) := sys->stat("/dis/wm/wm.dis");
	if(ok >= 0)
		(ok, nil) = sys->stat("/dis/wm/logon.dis");
	if(ok >= 0 && userok(user)){
		wm := load Command "/dis/wm/wm.dis";
		if(wm != nil){
			fd := sys->open("/nvfs/user", Sys->OWRITE);
			if(fd != nil){
				sys->fprint(fd, "%s", user);
				fd = nil;
			}
			spawn wm->init(nil, list of {"wm/wm", "wm/logon", "-l", "-n", "lib/ipaqns", "-u", user});
			exit;
		}
		sys->print("init: can't load wm/logon: %r");
	}
	sh := load Command Sh->PATH;
	if(sh == nil){
		err(sys->sprint("can't load %s: %r", Sh->PATH));
		hang();
	}
	spawn sh->init(nil, "sh" :: nil);
}

start(cmd: string, args: list of string)
{
	disfile := cmd;
	if(disfile[0] != '/')
		disfile = "/dis/"+disfile+".dis";
	(ok, nil) := sys->stat(disfile);
	if(ok >= 0){
		dis := load Command disfile;
		if(dis == nil)
			sys->print("init: can't load %s: %r\n", disfile);
		else
			spawn dis->init(nil, cmd :: args);
	}
}

dobind(f, t: string, flags: int)
{
	if(sys->bind(f, t, flags) < 0)
		err(sys->sprint("can't bind %s on %s: %r", f, t));
}

lightup()
{
	# backlight
	fd := sys->open("#T/ipaqctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "light 1 1 0x80");
}

#
# Set system name from nvram if possible
#
setsysname(def: string)
{
	v := array of byte def;
	fd := sys->open("/nvfs/ID", sys->OREAD);
	if(fd == nil)
		fd = sys->open("/env/sysname", sys->OREAD);
	if(fd != nil){
		buf := array[Sys->NAMEMAX] of byte;
		nr := sys->read(fd, buf, len buf);
		while(nr > 0 && buf[nr-1] == byte '\n')
			nr--;
		if(nr > 0)
			v = buf[0:nr];
	}
	fd = sys->open("/dev/sysname", sys->OWRITE);
	if(fd != nil)
		sys->write(fd, v, len v);
}

getclock(timefile: string, timedir: string): big
{
	now := big 0;
	if(timefile != nil){
		fd := sys->open(timefile, Sys->OREAD);
		if(fd != nil){
			b := array[64] of byte;
			n := sys->read(fd, b, len b-1);
			if(n > 0){
				now = big string b[0:n];
				if(now <= big 16r20000000)
					now = big 0;	# remote itself is not initialised
			}
		}
	}
	if(now == big 0){
		if(timedir != nil){
			(ok, dir) := sys->stat(timedir);
			if(ok < 0) {
				sys->print("init: stat %s: %r", timedir);
				return big 0;
			}
			now = big dir.atime;
		}else{
			now = big 993826747000000;
			sys->print("time warped\n");
		}
	}
	return now;
}

setclock(timefile: string, now: big)
{
	fd := sys->open(timefile, sys->OWRITE);
	if (fd == nil) {
		sys->print("init: can't open %s: %r", timefile);
		return;
	}

	b := sys->aprint("%ubd", now);
	if (sys->write(fd, b, len b) != len b)
		sys->print("init: can't write to %s: %r", timefile);
}

srv()
{
	sys->print("remote debug srv...");
	fd := sys->open("/dev/eia0ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "b115200");

	fd = sys->open("/dev/eia0", Sys->ORDWR);
	if (fd == nil){
		err(sys->sprint("can't open /dev/eia0: %r"));
		return;
	}
	if (sys->export(fd, "/", Sys->EXPASYNC) < 0){
		err(sys->sprint("can't export on serial port: %r"));
		return;
	}
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "init: %s\n", s);
}

hang()
{
	<-(chan of int);
}

tried := 0;

askrootsource(localok: int, netok: int): (string, string)
{
	stdin := sys->fildes(0);
	sources := "kernel" :: nil;
	if(netok)
		sources = "remote" :: sources;
	if(localok){
		sources = "local" :: sources;
		if(netok)
			sources = "local+remote" :: sources;
	}
Query:
	for(;;) {
		s := "";
		if (tried == 0 && (s = rdenv("rootsource", nil)) != nil) {
			tried = 1;
			if (s[len s - 1] == '\n')
				s = s[:len s - 1];
			sys->print("/nvfs/rootsource: root from %s\n", s);
		} else {
			sys->print("root from (");
			cm := "";
			for(l := sources; l != nil; l = tl l){
				sys->print("%s%s", cm, hd l);
				cm = ",";
			}
			sys->print(")[%s] ", hd sources);

			s = getline(stdin, hd sources);	# default
		}
		case s[0] {
		Keyboard->Right or Keyboard->Left =>
			sources = append(hd sources, tl sources);
			sys->print("\n");
			continue Query;
		Keyboard->Down =>
			s = hd sources;
			sys->print(" %s\n", s);
		}
		(nil, choice) := sys->tokenize(s, "\t ");
		if(choice == nil)
			choice = sources;
		opt := hd choice;
		case opt {
		* =>
			sys->print("\ninvalid boot option: '%s'\n", opt);
		"kernel" =>
			return (nil, "#r/rtc");
		"local" =>
			return ("/n/local", "#r/rtc");
		"local+remote" =>
			if(netfs("/n/remote") >= 0)
				return ("/n/local", "/n/remote/dev/time");
		"remote" =>
			if(netfs("/n/remote") >= 0)
				return ("/n/remote", "/n/remote/dev/time");
		}
	}
}

getline(fd: ref Sys->FD, default: string): string
{
	result := "";
	buf := array[10] of byte;
	i := 0;
	for(;;) {
		n := sys->read(fd, buf[i:], len buf - i);
		if(n < 1)
			break;
		i += n;
		while(i >0 && (nutf := sys->utfbytes(buf, i)) > 0){
			s := string buf[0:nutf];
			for (j := 0; j < len s; j++)
				case s[j] {
				'\b' =>
					if(result != nil)
						result = result[0:len result-1];
				'u'&16r1F =>
					sys->print("^U\n");
					result = "";
				'\r' =>
					;
				* =>
					sys->print("%c", s[j]);
					if(s[j] == '\n' || s[j] >= 16r80){
						if(s[j] != '\n')
							result[len result] = s[j];
						if(result == nil)
							return default;
						return result;
					}
					result[len result] = s[j];
				}
			buf[0:] = buf[nutf:i];
			i -= nutf;
		}
	}
	return default;
}

append(v: string, l: list of string): list of string
{
	if(l == nil)
		return v :: nil;
	return hd l :: append(v, tl l);
}

#
# serve local DOS or kfs file system using flash translation layer
#
lfs(): int
{
	if(!flashpart("#F/flash/flashctl", flashparts))
		return -1;
	if(!ftlinit("#F/flash/fs"))
		return -1;
	if(iskfs("#X/ftldata"))
		return lkfs("#X/ftldata");
	c := chan of string;
	spawn startfs(c, "/dis/dossrv.dis", "dossrv" :: "-f" :: "#X/ftldata" :: "-m" :: "/n/local" :: nil, nil);
	if(<-c != nil)
		return -1;
	return 0;
}

wmagic := "kfs wren device\n";

iskfs(file: string): int
{
	fd := sys->open(file, Sys->OREAD);
	if(fd == nil)
		return 0;
	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < len buf)
		return 0;
	if(string buf[256:256+len wmagic] != wmagic)
		return 0;
	RBUFSIZE := int string buf[256+len wmagic:256+len wmagic+12];
	if(RBUFSIZE % 512)
		return 0;	# bad block size
	return 1;
}

lkfs(file: string): int
{
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		return -1;
	c := chan of string;
	spawn startfs(c, "/dis/disk/kfs.dis", "disk/kfs" :: "-A" :: "-n" :: "main" :: file :: nil, p[0]);
	if(<-c != nil)
		return -1;
	p[0] = nil;
	return sys->mount(p[1], nil, "/n/local", Sys->MREPL|Sys->MCREATE, nil);
}

startfs(c: chan of string, file: string, args: list of string, fd: ref Sys->FD)
{
	if(fd != nil){
		sys->pctl(Sys->NEWFD, fd.fd :: 1 :: 2 :: nil);
		sys->dup(fd.fd, 0);
	}
	fs := load Command file;
	if(fs == nil){
		sys->print("can't load %s: %r\n", file);
		c <-= "load failed";
	}
	{
		fs->init(nil, args);
		c <-= nil;
	}exception {
	"*" =>
		c <-= "failed";
	* =>
		c <-= "unknown exception";
	}
}

#
# partition flash
#
flashdone := 0;

flashpart(ctl: string, parts: array of string): int
{
	if(flashdone)
		return 1;
	cfd := sys->open(ctl, Sys->ORDWR);
	if(cfd == nil){
		sys->print("can't open %s: %r\n", ctl);
		return 0;
	}
	for(i := 0; i < len parts; i++)
		if(sys->fprint(cfd, "%s", parts[i]) < 0){
			sys->print("can't %q to %s: %r\n", parts[i], ctl);
			return 0;
		}
	flashdone = 1;
	return 1;
}

#
# set up flash translation layer
#
ftldone := 0;

ftlinit(flashmem: string): int
{
	if(ftldone)
		return 1;
	sys->print("Set flash translation of %s...\n", flashmem);
	fd := sys->open("#X/ftlctl", Sys->OWRITE);
	if(fd == nil){
		sys->print("can't open #X/ftlctl: %r\n");
		return 0;
	}
	if(sys->fprint(fd, "init %s", flashmem) <= 0){
		sys->print("can't init flash translation: %r\n");
		return 0;
	}
	ftldone = 1;
	return 1;
}

configether()
{
	if(ethername == nil)
		return;
	fd := sys->open("/nvfs/etherparams", Sys->OREAD);
	if(fd == nil)
		return;
	ctl := sys->open("/net/"+ethername+"/clone", Sys->OWRITE);
	if(ctl == nil){
		sys->print("init: can't open %s's clone: %r\n", ethername);
		return;
	}
	b := array[1024] of byte;
	n := sys->read(fd, b, len b);
	if(n <= 0)
		return;
	for(i := 0; i < n;){
		for(e := i; e < n && b[e] != byte '\n'; e++)
			;
		s := string b[i:e];
		if(sys->fprint(ctl, "%s", s) < 0)
			sys->print("init: ctl write to %s: %s: %r\n", ethername, s);
		i = e+1;
	}
}

donebind := 0;

#
# set up network mount
#
netfs(mountpt: string): int
{
	fd: ref Sys->FD;
	if(!donebind){
		fd = sys->open("/net/ipifc/clone", sys->OWRITE);
		if(fd == nil) {
			sys->print("init: open /net/ipifc/clone: %r\n");
			return -1;
		}
		if(sys->fprint(fd, "bind ether %s", ethername) < 0) {
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
	server := rdenv("fsip", nil);
	if((ip := rdenv("ip", nil)) != nil) {
		sys->print("**using %s\n", ip);
		sys->fprint(fd, "bind ether /net/ether0");
		sys->fprint(fd, "add %s ", ip);
		if((ipgw := rdenv("ipgw", nil)) != nil){
			rfd := sys->open("/net/iproute", Sys->OWRITE);
			if(rfd != nil){
				sys->fprint(rfd, "add 0 0 %s", ipgw);
				sys->print("**using ipgw=%s\n", ipgw);
			}
		}
	}else if(server == nil){
		sys->print("dhcp...");
		dhcpclient = load Dhcpclient Dhcpclient->PATH;
		if(dhcpclient == nil){
			sys->print("can't load dhcpclient: %r\n");
			return -1;
		}
		dhcpclient->init();
		(cfg, nil, e) := dhcpclient->dhcp("/net", fd, "/net/ether0/addr", nil, nil);
		if(e != nil){
			sys->print("dhcp: %s\n", e);
			return -1;
		}
		if(server == nil)
			server = cfg.getip(Dhcpclient->OP9fs);
		dhcpclient = nil;
	}
	if(server == nil || server == "0.0.0.0"){
		sys->print("no file server address\n");
		return -1;
	}
	sys->print("fs=%s\n", server);

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

calibrate()
{
	val := rf("/nvfs/calibrate", nil);
	if(val != nil){
		fd := sys->open("/dev/touchctl", Sys->OWRITE);
		if(fd != nil && sys->fprint(fd, "%s", val) >= 0)
			return;
	}
	done := chan of int;
	spawn docal(done);
	<-done;
}

docal(done: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	ofd := sys->create("/nvfs/calibrate", Sys->OWRITE, 8r644);
	if(ofd != nil)
		sys->dup(ofd.fd, 1);
	cal := load Command "/dis/touchcal.dis";
	if(cal != nil){
		{
			cal->init(nil, "touchcal" :: nil);
		}exception{
		"fail:*" =>
			;
		}
	}
	done <-= 1;
}

userok(user: string): int
{
	(ok, d) := sys->stat("/usr/"+user);
	return ok >= 0 && (d.mode & Sys->DMDIR) != 0;
}

rdenv(name: string, def: string): string
{
	s := rf("#e/"+name, nil);
	if(s != nil)
		return s;
	s = rf("/nvfs/"+name, def);
	while(s != nil && ((c := s[len s-1]) == '\n' || c == '\r'))
		s = s[0: len s-1];
	if(s != nil)
		return s;
	return def;
}

rf(file: string, default: string): string
{
	fd := sys->open(file, Sys->OREAD);
	if(fd != nil){
		buf := array[128] of byte;
		nr := sys->read(fd, buf, len buf);
		if(nr > 0)
			return string buf[0:nr];
	}
	return default;
}
