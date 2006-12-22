#
# Intrinsyc Cerf cube 405EP, also Manga switch
#
# this encrusted version will be simplified shortly
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

include "sh.m";

Init: module
{
	init:	fn();
};

Bootpreadlen: con 128;
Microsec: con 1000000;
Notime: con big 800000000 * big Microsec;	# fairly arbitrary time in 1995 to check validity

# conventional Inferno NAND flash partitions
nandparts := array[] of {
	# bootstrap from 0 to 0x210000
	"add boot 0 0x210000",
	"add fs 0x210000 end"
};

userdefault := array[] of {
	"inferno inferno",
	"sys sys"
};

ethername := "/net/ether0";

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

	sys->bind("/", "/", Sys->MREPL);
	if(sys->bind("/boot", "/", Sys->MAFTER) < 0)
		sys->print("can't bind /boot after /: %r\n");
	sys->bind("/boot/nvfs", "/nvfs", Sys->MREPL);

	auth = load Auth Auth->PATH;
	if(auth != nil)
		auth->init();

	localok := 0;
	if(lfs() >= 0){
		# let's just take a closer look
		sys->bind("/n/local/nvfs", "/nvfs", Sys->MBEFORE|Sys->MCREATE);
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
			ethername = "/net/ether1";
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
	sys->bind("#ʟ", "/dev", Sys->MAFTER);	# logfs

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
			sys->bind("/n/local", rootsource+"/n/local", Sys->MREPL|Sys->MCREATE);
			sys->unmount("#//./boot", "/");
			sys->bind(rootsource+"/dis", "/dis", Sys->MBEFORE|Sys->MCREATE);
			break;
		}
	}
	cfd = nil;

	setsysname("cerf");			# set system name

	rtc := big rf("#r/rtc", "0") * big Microsec;
	now := big 0;
	if(timefile != nil){	# synchronise with remote time if it's valid
		now = big rf(timefile, "0");
		if(now < Notime && rootsource != nil)
			now = big filetime(rootsource) * big Microsec;	# try the time of the root directory
		if(now >= Notime){
			setclock("#r/rtc", now/big Microsec);
			rtc = now;
		}
	}
	if(now < Notime)
		now = rtc;
	setclock("/dev/time", now);

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
	user := rdenv("user", "inferno");
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

filetime(name: string): int
{
	(ok, dir) := sys->stat(name);
	if(ok < 0)
		return 0;
	return dir.atime;
}

setclock(timefile: string, now: big)
{
	fd := sys->open(timefile, sys->OWRITE);
	if(fd == nil)
		sys->print("init: can't open %s: %r\n", timefile);
	else if(sys->fprint(fd, "%bud", now) < 0)
		sys->print("init: can't write to %s: %r\n", timefile);
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
	for(;;){
		s := "";
		if(tried == 0 && (s = rdenv("rootsource", nil)) != nil){
			tried = 1;
			sys->print("rootsource: root from %s\n", s);
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
			return (nil, nil);
		"local" =>
			return ("/n/local", nil);
		"local+remote" =>
			if(netfs("/n/remote") >= 0)
				return ("/n/local", nil);
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
	for(;;){
		n := sys->read(fd, buf[i:], len buf - i);
		if(n < 1)
			break;
		i += n;
		while(i >0 && (nutf := sys->utfbytes(buf, i)) > 0){
			s := string buf[0:nutf];
			for(j := 0; j < len s; j++)
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
# serve local file system using logfs
#
lfs(): int
{
	if(!flashpart("#F1/flash1/flashctl", nandparts))
		return -1;
	if(!logfsinit("#F1/flash1/fs"))
		return -1;
	mfd := sys->open("/dev/logfsmain", Sys->ORDWR);
	if(mfd == nil){
		sys->print("can't open /dev/logfsmain: %r\n");
		return -1;
	}
	if(sys->mount(mfd, nil, "/n/local", Sys->MREPL|Sys->MCREATE, nil) < 0){
		sys->print("can't mount /dev/logfsmain on /n/local: %r\n");
		return -1;
	}
	return 0;
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
# set up logfs
#
logfsdone := 0;

logfsinit(flashmem: string): int
{
	if(logfsdone)
		return 1;
	fd := sys->open("/dev/logfsctl", Sys->OWRITE);
	if(fd == nil){
		if(sys->bind("#ʟ", "/dev", Sys->MBEFORE) < 0)
			return -1;
		fd = sys->open("/dev/logfsctl", Sys->OWRITE);
		if(fd == nil){
			sys->print("can't open /dev/logfsctl: %r\n");
			return -1;
		}
	}
	sys->print("Set logfs main on %s...\n", flashmem);
	if(!ctlw(fd, "logfs", "fsys main config "+flashmem))
		return -1;
	if(!ctlw(fd, "logfs", "fsys main"))
		return -1;
	cm := rf("#e/logfsformat", nil);
	if(cm == "yes"){
		if(!ctlw(fd, "logfs", "format 0"))
			return -1;
	}
	cf := rf("#e/logfsopen", nil);
	if(cf == nil)
		cf = "open";
	if(!ctlw(fd, "logfs", cf))
		return -1;
	for(i := 0; i < len userdefault; i++)
		ctlw(fd, "logfs", "uname "+userdefault[i]);
	logfsdone = 1;
	return 1;
}

ctlw(fd: ref Sys->FD, w: string, cmd: string): int
{
	if(sys->fprint(fd, "%s", cmd) < 0){
		sys->print("%s ctl %q: %r\n", w, cmd);
		return 0;
	}
	return 1;
}

configether()
{
	if(ethername == nil)
		return;
	fd := sys->open("/nvfs/etherparams", Sys->OREAD);
	if(fd == nil)
		return;
	ctl := sys->open(ethername+"/clone", Sys->OWRITE);
	if(ctl == nil){
		sys->print("init: can't open %s/clone: %r\n", ethername);
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
			sys->print("init: ctl write to %s/clone: %s: %r\n", ethername, s);
		i = e+1;
	}
}

donebind := 0;
server: string;

#
# set up network mount
#
netfs(mountpt: string): int
{
	fd: ref Sys->FD;
	if(!donebind){
		fd = sys->open("/net/ipifc/clone", sys->OWRITE);
		if(fd == nil){
			sys->print("init: open /net/ipifc/clone: %r\n");
			return -1;
		}
		if(sys->fprint(fd, "bind ether %s", ethername) < 0){
			sys->print("could not bind %s interface: %r\n", ethername);
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
	server = rdenv("fsip", nil);
	if((ip := rdenv("ip", nil)) != nil){
		sys->print("**using %s\n", ip);
		sys->fprint(fd, "bind ether /net/ether0");
		s := rdenv("ipmask", nil);
		if(s == nil)
			s = rdenv("netmask", nil);	# alternative name used by some bootstraps
		sys->fprint(fd, "add %s %s", ip, s);
		gate := rdenv("ipgw", nil);
		if(gate == nil)
			gate = rdenv("gateway", nil);
		if(gate != nil){
			rfd := sys->open("/net/iproute", Sys->OWRITE);
			if(rfd != nil){
				sys->fprint(rfd, "add 0 0 %s", gate);
				sys->print("set gateway %s\n", gate);
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
			sys->print("trying mount as `none'\n");
		}
		(c.dfd, err) = auth->client("none", ai, c.dfd);
		if(c.dfd == nil){
			sys->print("authentication failed: %s\n", err);
			return -1;
		}
	}

	sys->print("mount %s...", mountpt);

	c.cfd = nil;
	n := sys->mount(c.dfd, nil, mountpt, Sys->MREPL, "");
	if(n > 0)
		return 0;
	if(n < 0)
		sys->print("%r");
	return -1;
}
	
username(def: string): string
{
	return rdenv("user", def);
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
	return rf("/nvfs/"+name, def);
}

rf(file: string, default: string): string
{
	fd := sys->open(file, Sys->OREAD);
	if(fd != nil){
		buf := array[128] of byte;
		nr := sys->read(fd, buf, len buf);
		if(nr > 0){
			s := string buf[0:nr];
			while(s != nil && ((c := s[len s-1]) == '\n' || c == '\r'))
				s = s[0: len s-1];
			if(s != nil)
				return s;
		}
	}
	return default;
}
