#
# Generalized boot Inferno
#

implement Init;

include "sys.m";
	sys:	Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "security.m";
	auth: Auth;
	random: Random;

include "tftp.m";

Bootpreadlen: con 128;

Init: module
{
	init:	fn();
};

ip: string;
mask: string;
fsip: string;
bootprotocol: string;
bootserver: string;
bootfile: string;

debug: con 0;

init()
{
	ipavailable: int;
	sys = load Sys Sys->PATH;

	kexecfd := sys->open("#B/kexec", Sys->OWRITE);
	if (kexecfd == nil)
		fatal(sys->sprint("opening #B/kexec: %r"));

	ipavailable = 0;
	if (dobind("#l", "/net", sys->MREPL) && dobind("#I", "/net", sys->MAFTER))
		ipavailable = 1;

	dobind("#c", "/dev", sys->MAFTER); 	# console device

	if (!ipavailable)
		fatal("no IP stack available");
	cfd := sys->open("/net/ipifc/clone", sys->ORDWR);
	if(cfd == nil)
		fatal(sys->sprint("open /net/ipifc/clone: %r"));

	if (sys->fprint(cfd, "bind ether ether0") < 0)
		fatal(sys->sprint("binding ether0: %r"));

	fsready := 0;

	fsip = ipconfig(cfd);

	bootstring := getenvdefault("bootpath", "tftp");

	(bootprotocol, bootserver, bootfile) = parsebootstring(bootstring);

	if (bootprotocol == nil)
		fatal(bootstring + ": unrecognised syntax");

	# Run dhcp if necessary
	if (bootprotocol == "tftp" && (bootserver == nil || bootfile == nil))
		dhcp();

	# determine server
	if (bootprotocol == "net" && bootserver == nil)
		bootserver = fsip;

	if (bootserver == nil)
		fatal("couldn't determine boot server");

	if (bootfile == nil)
		fatal("couldn't determine boot file");

	if (bootprotocol == nil)
		fatal("couldn't determine boot protocol");

	sys->print("loading %s!%s!%s\n", bootprotocol, bootserver, bootfile);

	if (bootprotocol == "net") {
		sys->print("Attempting remote mount\n");
		if (netfs(bootserver) == 0)
			sys->print("Remote mount successful\n");
		else
			fatal(sys->sprint("Remote mount failed: %r"));
		fd := sys->open("/n/remote" + bootfile, Sys->OREAD);
		if (fd == nil)
			fatal(sys->sprint("%s:/n/remote%s: %r", bootserver, bootfile));
		if (sys->stream(fd, kexecfd, 4096) < 0)
			fatal(sys->sprint("copying %s: %r", bootfile));
	}
	else if (bootprotocol == "tftp") {
		tftp := load Tftp Tftp->PATH;
		if (tftp == nil)
			fatal("can't load tftp module");
		tftp->init(1);
		errstr := tftp->receive(bootserver, bootfile, kexecfd);
		if (errstr != nil)
			fatal("tftp: " + errstr);
	}
	else
		fatal("protocol " + bootprotocol + " not supported");
	sys->print("Launching new kernel\n");
	kexecfd = nil;
}

parsebootstring(s: string): (string, string, string)
{
	proto, server, file: string;
	(n, l) := sys->tokenize(s, "!");
	if (n > 3)
		return (nil, nil, nil);
	proto = hd l;
	l = tl l;
	if (l != nil) {
		server = hd l;
		l = tl l;
	}
	if (l != nil)
		file = hd l;
	case proto {
	"tftp" =>
		;
	"net" =>
		# can't have a default file, so n must be 3
		if (n != 3)
			return (nil, nil, nil);
	* =>
		return (nil, nil, nil);
	}
	return (proto, server, file);
}

dobind(f, t: string, flags: int): int
{
	if(sys->bind(f, t, flags) < 0) {
		err(sys->sprint("can't bind %s on %s: %r", f, t));
		return 0;
	}
	return 1;
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "bootinit: %s\n", s);
}

hang()
{
	<-(chan of int);
}

fatal(s: string)
{
	err(s);
	hang();
}

envlist: list of string;

getenv(name: string): string
{
	if (envlist == nil) {
		fd := sys->open("/dev/sysenv", Sys->OREAD);
		if (fd != nil) {
			ntok: int;
			buf := array[1024] of byte;
			nr := sys->read(fd, buf, len buf);
			if(nr > 0)
				(ntok, envlist) = sys->tokenize(string buf, "\n");
		}
	}
	ls := envlist;
	while(ls != nil) {
		(ntok2, ls2) := sys->tokenize(hd ls, "=");
		if(hd ls2 == name)
			return hd tl ls2;
		ls = tl ls;
	}
	return nil;
}

getenvdefault(name: string, default: string): string
{
	rv := getenv(name);
	if (rv == nil)
		return default;
	return rv;
}

ipconfig(cfd: ref sys->FD): string
{
	ip = getenv("wireip");
	if (ip == nil)
		ip = getenv("ip");
	mask = getenv("ipmask");
	fsip = getenv("fsip");
	if (ip != nil && mask != nil) {
		sys->print("ip %s %s\n", ip, mask);
		sys->fprint(cfd, "add %s %s", ip, mask);
		gwip := getenv("gwip");
		if (gwip != nil) {
			sys->print("gwip %s\n", gwip);
			rfd := sys->open("/net/iproute", Sys->ORDWR);
			if (rfd == nil || sys->fprint(rfd, "add 0.0.0.0 0.0.0.0 %s", gwip) < 0)
				err(sys->sprint("failed to add default route: %r"));
		}
	}
	if (ip == nil || mask == nil)
		return bootp(cfd);
	return fsip;
}

bootpdone: int;

bootp(cfd: ref sys->FD): string
{
	if (bootpdone == 1)
		return fsip;

	bootpdone = 1;

	sys->print("bootp ...");

	if (sys->fprint(cfd, "bootp") < 0) {
		sys->print("init: bootp: %r");
		return nil;
	}

	fd := sys->open("/net/bootp", sys->OREAD);
	if(fd == nil) {
		err(sys->sprint("open /net/bootp: %r"));
		return nil;
	}

	buf := array[Bootpreadlen] of byte;
	nr := sys->read(fd, buf, len buf);
	fd = nil;
	if(nr <= 0) {
		err(sys->sprint("read /net/bootp: %r"));
		return nil;
	}
	(ntok, ls) := sys->tokenize(string buf, " \t\n");
	while(ls != nil) {
		name := hd ls;
		ls = tl ls;
		if (ls == nil)
			break;
		value := hd ls;
		ls = tl ls;
		if (name == "fsip")
			fsip = value;
		else if (name == "ipaddr")
			ip = value;
		else if (name == "ipmask")
			mask = value;
	}
	return fsip;
}

netfs(server: string): int
{
	auth = load Auth  Auth->PATH;
	if (auth != nil)
		auth->init();

	kr = load Keyring Keyring->PATH;
	sys->print("dial...");
	(ok, c) := sys->dial("tcp!" + server + "!6666", nil);
	if(ok < 0)
		return -1;
	
	if(kr != nil && auth != nil){
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
	
	sys->print("mount ...");
	
	c.cfd = nil;
	n := sys->mount(c.dfd, nil, "/n/remote", sys->MREPL, "");
	if(n > 0)
		return 0;
	return -1;
}

#
#
# DHCP
#
#

Dhcp: adt {
	op: int;
	htype: int;
	hops: int;
	xid: int;
	secs: int;
	flags: int;
	ciaddr: int;
	yiaddr: int;
	siaddr: int;
	giaddr: int;
	chaddr: array of byte;
	sname: string;
	file: string;
};

nboputl(buf: array of byte, val: int)
{
	buf[0] = byte (val >> 24);
	buf[1] = byte (val >> 16);
	buf[2] = byte (val >> 8);
	buf[3] = byte val;
}

nboputs(buf: array of byte, val: int)
{
	buf[0] = byte (val >> 8);
	buf[1] = byte val;
}

nbogets(buf: array of byte): int
{
	return (int buf[0] << 8) | int buf[1];
}

nbogetl(buf: array of byte): int
{
	return (int buf[0] << 24) | (int buf[1] << 16) | (int buf[2] << 8) | int buf[3];
}

stringget(buf: array of byte): string
{
	for (x := 0; x < len buf; x++)
		if (buf[x] == byte 0)
			break;
	if (x == 0)
		return nil;
	return string buf[0 : x];
}

memcmp(b1: array of byte, b2: array of byte): int
{
	l := len b1;
	if (l < len b2)
		return int -b2[l];
	if (l > len b2)
		return int b1[l];
	for (i := 0; i < l; i++) {
		d := int b1[i] - int b2[i];
		if (d != 0)
			return d;
	}
	return 0;
}

memncpy(out: array of byte, in: array of byte)
{
	if (in == nil)
		return;
	l := len in;
	if (l > len out)
		l = len out;
	out[0 :] = in[0 : l];
}

memset(out: array of byte, val: byte)
{
	for (l := 0; l < len out; l++)
		out[l] = val;
}

dhcpsend(dfd: ref Sys->FD, dhcp: ref Dhcp)
{
	buf := array[576] of byte;
	buf[0] = byte dhcp.op;
	buf[1] = byte dhcp.htype;
	buf[2] = byte len dhcp.chaddr;
	buf[3] = byte dhcp.hops;
	nboputl(buf[4 : 8], dhcp.xid);
	nboputs(buf[8 : 10], dhcp.secs);
	nboputs(buf[10 : 12], dhcp.flags);
	nboputl(buf[12 : 16], dhcp.ciaddr);
	nboputl(buf[16 : 20], dhcp.yiaddr);
	nboputl(buf[20 : 24], dhcp.siaddr);
	nboputl(buf[24 : 28], dhcp.giaddr);
	memset(buf[28 :], byte 0);
	memncpy(buf[28 : 44], dhcp.chaddr);
	memncpy(buf[44 : 108], array of byte dhcp.sname);
	memncpy(buf[108 : 236], array of byte dhcp.file);
	sys->write(dfd, buf, len buf);
}

kill(pid: int)
{
	fd := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if (fd == nil)
		return;

	msg := array of byte "kill";
        sys->write(fd, msg, len msg);
}

ipfmt(ipaddr: int): string
{
	return sys->sprint("%ud.%ud.%ud.%ud",
		(ipaddr >> 24) & 16rff,
		(ipaddr >> 16) & 16rff,
		(ipaddr >> 8) & 16rff,
		ipaddr & 16rff);
}

dumpdhcp(dhcp: ref Dhcp)
{
	sys->print("op %d htype %d hops %d xid %ud\n", dhcp.op, dhcp.htype, dhcp.hops, dhcp.xid);
	sys->print("secs %d flags 0x%.4ux\n", dhcp.secs, dhcp.flags);
	sys->print("ciaddr %s\n", ipfmt(dhcp.ciaddr));
	sys->print("yiaddr %s\n", ipfmt(dhcp.yiaddr));
	sys->print("siaddr %s\n", ipfmt(dhcp.siaddr));
	sys->print("giaddr %s\n", ipfmt(dhcp.giaddr));
	sys->print("chaddr ");
	for (x := 0; x < len dhcp.chaddr; x++)
		sys->print("%.2ux", int dhcp.chaddr[x]);
	sys->print("\n");
	if (dhcp.sname != nil)
		sys->print("sname %s\n", dhcp.sname);
	if (dhcp.file != nil)
		sys->print("file %s\n", dhcp.file);
}

dhcplisten(pidc: chan of int, fd: ref Sys->FD, dc: chan of ref Dhcp)
{
	pid := sys->pctl(0, nil);
	pidc <-= pid;
	buf := array [576] of byte;
	while (1) {
		n := sys->read(fd, buf, len buf);
		dhcp := ref Dhcp;
		dhcp.op = int buf[0];
		dhcp.htype = int buf[1];
		hlen := int buf[2];
		dhcp.hops = int buf[3];
		dhcp.xid = nbogetl(buf[4 : 8]);
		dhcp.secs = nbogets(buf[8 : 10]);
		dhcp.flags = nbogets(buf[10 : 12]);
		dhcp.ciaddr = nbogetl(buf[12 : 16]);
		dhcp.yiaddr = nbogetl(buf[16 : 20]);
		dhcp.siaddr = nbogetl(buf[20 : 24]);
		dhcp.giaddr = nbogetl(buf[24: 28]);
		dhcp.chaddr = buf[28 : 28 + hlen];
		dhcp.sname = stringget(buf[44 : 108]);
		dhcp.file = stringget(buf[108 : 236]);
		dc <-= dhcp;
	}
}
	
timeoutproc(pid: chan of int, howlong: int, c: chan of string)
{
	pid <-= sys->pctl(0, nil);

	sys->sleep(howlong);

	# send timeout
	c <-= "timed out";
}

tpid := -1;
tc: chan of string;

timeoutcancel()
{
	if (tpid >= 0) {
		kill(tpid);
		tpid = -1;
	}
}

timeoutstart(howlong: int): (chan of string)
{
	timeoutcancel();
	pidc := chan of int;
	tc = chan of string;
	spawn timeoutproc(pidc, howlong, tc);
	tpid = <- pidc;
	return tc;
}

atohn(b: byte): int
{
	if (b >= byte '0' && b <= byte '9')
		return int (b - byte '0');
	if (b >= byte 'A' && b <= byte 'F')
		return int b - 'A' + 10;
	if (b >= byte 'a' && b <= byte 'f')
		return int b - 'a' + 10;
	return -1;
}

atohb(buf: array of byte): int
{
	tn := atohn(buf[0]);
	bn := atohn(buf[1]);
	if (tn < 0 || bn < 0)
		return -1;
	return tn * 16 + bn;
}

gethaddr(dhcp: ref Dhcp): int
{
	fd := sys->open("#l/ether0/addr", Sys->OREAD);
	if (fd == nil)
		return 0;
	buf := array [100] of byte;
	n := sys->read(fd, buf, len buf);
	if (n < 0)
		return 0;
	dhcp.htype = 1;
	hlen := n / 2;
	dhcp.chaddr = array [hlen] of byte;
	for (i := 0; i < hlen; i++)
		dhcp.chaddr[i] = byte atohb(buf[i * 2 : i * 2 + 2]);
	return 1;
}

parsedq(dq: string): (int, int)
{
	(c, l) := sys->tokenize(dq, ".");
	if (c != 4)
		return (0, 0);
	a := hd l;
	l = tl l;
	b := hd l;
	l = tl l;
	d := hd l;
	l = tl l;
	addr := (int a << 24) | (int b << 16) | (int d << 8) | int hd l;
	return (1, addr);
}

dhcp()
{
	ok: int;
	conn: Sys->Connection;
	rdhcp: ref Dhcp;

	if (random == nil)
		random = load Random Random->PATH;

	(ok, conn) = sys->dial("udp!255.255.255.255!67", "68");
	if (!ok)
		fatal(sys->sprint("failed to dial udp broadcast: %r"));

	pidc := chan of int;
	dc := chan of ref Dhcp;
	spawn dhcplisten(pidc, conn.dfd, dc);
	dhcppid := <- pidc;
	dhcp := ref Dhcp;
	dhcp.op = 1;
	dhcp.htype  = 1;
	gethaddr(dhcp);
	dhcp.hops = 0;
	dhcp.xid = random->randomint(Random->NotQuiteRandom);
	dhcp.secs = 0;
	dhcp.flags = 0;
	(ok, dhcp.ciaddr) = parsedq(ip);
	dhcp.yiaddr = 0;
	dhcp.siaddr = 0;
	dhcp.giaddr = 0;
	if (bootfile != "bootp")
		dhcp.file = bootfile;
	else
		dhcp.file = nil;
	ok = 0;
	for (count := 0; !ok && count < 5; count++) {
		mtc := timeoutstart(3000);
		dhcpsend(conn.dfd, dhcp);
		timedout := 0;
		do {
			alt {
				<- mtc =>
					timedout = 1;
				rdhcp = <- dc =>
					if (debug)
						dumpdhcp(rdhcp);
					if (rdhcp.ciaddr != dhcp.ciaddr || rdhcp.xid != dhcp.xid
						|| memcmp(rdhcp.chaddr, dhcp.chaddr) != 0) {
						break;
					}
					if (rdhcp.file != nil) {
						ok = 1;
						timeoutcancel();
					}
			}
		} while (!timedout && !ok);
		dhcp.xid++;
	}
	if (ok) {
		if (bootfile == nil)
			bootfile = rdhcp.file;
		if (bootserver == nil)
			bootserver = ipfmt(rdhcp.siaddr);
	}
	else
		err("bootp timed out");
	kill(dhcppid);
}
