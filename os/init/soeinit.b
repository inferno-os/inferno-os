#
# Soekris 4501
#

implement Init;

include "sys.m";
	sys:	Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "security.m";
	auth: Auth;

include "sh.m";

Init: module
{
	init:	fn();
};

Bootpreadlen: con 128;

# standard flash partitions

#flashparts := array[] of {
#	# bootstrap at 0x0 to 0x20000
#	"add script 0x20000 0x40000",
#	"add kernel 0x100000 0x200000",
#	"add fs 0x200000 end",
#};
flashparts: array of string;

ethername := "ether0";

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
	sys->bind("#d", "/fd", Sys->MREPL);
	dobind("#c", "/dev", sys->MREPL); 	# console
	dobind("#t", "/dev", sys->MAFTER);	# serial line
	drawok := sys->bind("#i", "/dev", sys->MAFTER) >= 0; 	# draw
	sys->bind("#m", "/dev", sys->MAFTER);	# pointer
	sys->bind("#e", "/env", sys->MREPL|sys->MCREATE);	# environment
	sys->bind("#A", "/dev", Sys->MAFTER);	# optional audio
	timefile: string;
	rootsource: string;
	scale := 1;
	cfd := sys->open("/dev/consctl", Sys->OWRITE);
	if(cfd != nil)
		sys->fprint(cfd, "rawon");
	for(;;){
		(rootsource, timefile, scale) = askrootsource(localok, netok);
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

	setsysname("soe");			# set system name

	now := getclock(timefile, rootsource);
	if(scale == 1)
		now *= big 1000000;
	setclock("/dev/time", now);
	if(timefile != "#r/rtc")
		setclock("#r/rtc", now/big 1000000);

	sys->chdir("/");
	if(netok){
		start("ndb/dns", nil);
		start("ndb/cs", nil);
	}
	startup := "/nvfs/startup";
	if(sys->open(startup, Sys->OREAD) != nil){
		shell := load Command Sh->PATH;
		if(shell != nil){
			sys->print("Running %s\n", startup);
			shell->init(nil, "sh" :: startup :: nil);
		}
	}
	user := username("inferno");
	(ok, nil) := sys->stat("/dis/wm/wm.dis");
	if(drawok && ok >= 0)
		(ok, nil) = sys->stat("/dis/wm/logon.dis");
	if(drawok && ok >= 0 && userok(user)){
		wm := load Command "/dis/wm/wm.dis";
		if(wm != nil){
			fd := sys->open("/nvfs/user", Sys->OWRITE);
			if(fd != nil){
				sys->fprint(fd, "%s", user);
				fd = nil;
			}
			spawn wm->init(nil, list of {"wm/wm", "wm/logon", "-l", "-u", user});
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
	<-chan of int;
}

tried := 0;

askrootsource(localok: int, netok: int): (string, string, int)
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
	for(;;) {
		s := "";
		if (tried == 0 && (s = rf("/nvfs/rootsource", nil)) != nil) {
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
		(nil, choice) := sys->tokenize(s, "\t ");
		if(choice == nil)
			choice = sources;
		opt := hd choice;
		case opt {
		* =>
			sys->print("\ninvalid boot option: '%s'\n", opt);
		"kernel" =>
			return (nil, "#r/rtc", 1);
		"local" =>
			return ("/n/local", "#r/rtc", 1);
		"local+remote" =>
			if(netfs("/n/remote") >= 0)
				return ("/n/local", "/n/remote/dev/time", 1000000);
		"remote" =>
			if(netfs("/n/remote") >= 0)
				return ("/n/remote", "/n/remote/dev/time", 1000000);
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

#
# serve local DOS file system using flash translation layer
#
lfs(): int
{
	if(!flashpart("#F/flash/flashctl", flashparts))
		return -1;
	if(!ftlinit("#F/flash/fs"))
		return -1;
	c := chan of string;
	spawn startfs(c, "/dis/dossrv.dis", "dossrv" :: "-f" :: "#X/ftldata" :: "-m" :: "/n/local" :: nil);
	if(<-c != nil)
		return -1;
	return 0;
}

startfs(c: chan of string, file: string, args: list of string)
{
	fs := load Command file;
	if(fs == nil){
		sys->print("can't load %s: %r\n", file);
		c <-= "load failed";
	}
	{
		fs->init(nil, args);
	}exception e {
	"*" =>
		c <-= "failed";
		exit;
	* =>
		c <-= "unknown exception";
		exit;
	}
	c <-= nil;
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
	sys->print("bootp ...");

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
	if ((ip := rf("/nvfs/ip", nil)) != nil) {
		sys->print("**using %s\n", ip);
		sys->fprint(fd, "bind ether /net/ether0");
		sys->fprint(fd, "add %s ", ip);
	} else {
		{
			if(sys->fprint(fd, "bootp") < 0)
				sys->print("could not bootp: %r\n");
		} exception e {
			"*" =>
				sys->print("could not bootp: %s\n", e);
		}
	}
	server := rf("/nvfs/fsip", nil);
	if (server != nil) {
		if (server[len server - 1] == '\n')
			server = server[:len server - 1];
		sys->print("/nvfs/fsip: server=%s\n", server);
	} else
		server = bootp();
	if(server == nil || server == "0.0.0.0")
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
	
username(def: string): string
{
	return rf("/nvfs/user", def);
}

userok(user: string): int
{
	(ok, d) := sys->stat("/usr/"+user);
	return ok >= 0 && (d.mode & Sys->DMDIR) != 0;
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
