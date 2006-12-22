implement Init;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "keyring.m";
	kr: Keyring;

include "security.m";
	auth: Auth;

include "styx.m";

	dosfs : Dosfs;

PROMPT:		con 1;		# boot from prompt?  (0 means boot from fs)
SHELL:		con 0;		# Start a Shell, not Logon
INIT: 		con "/init";	# file to read init commands from

startip := 0;

Bootpreadlen:	con 128;

Init: module
{
	init:	fn();
};

Logon: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Sh: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

lfs(dev: string): int
{
	(ok, dir) := sys->stat(dev);
	if (ok < 0) {
		sys->print("init: stat %s: %r\n", dev);
		return -1;
	}
	pipefd := array[2] of ref Sys->FD;
 	dosfs = load Dosfs "#/./dosfs";
	if(dosfs == nil) {
		sys->fprint(sys->fildes(2),"load #/.dosfs: %r\n");
		return -1;
	}

	dosfs->init(dev, "", 0);
	if(sys->pipe(pipefd) < 0){
		sys->fprint(sys->fildes(2),"pipe %r\n");
		exit;
	}
	spawn dosfs->dossrv(pipefd[1]);

	n := sys->mount(pipefd[0], "/", sys->MREPL|sys->MCREATE, "");
	if(n<0) {
		sys->print("couldn't mount. %r\n");
		return -1;
	}

	dosfs->setup();

	sys->print("mounted %s at /\n", dev);

	return 0;
}

ipinit()
{
	fd := sys->open("/nvfs/IP", sys->OREAD);
	if(fd == nil)
		return;

	buf := array[128] of byte;
	nr := sys->read(fd, buf, len buf);
	if(nr <= 0)
		return;

	cfd := sys->open("/net/ipifc/clone", sys->ORDWR);
	if(cfd == nil) {
		sys->print("init: open /net/ipifc/clone: %r");
		exit;
	}

	sys->fprint(cfd, "bind ether ether0");
	sys->fprint(cfd, "%s", string buf[0:nr]);
}

netfs(): int
{
	cfd := sys->open("/net/ipifc/clone", sys->ORDWR);
	if(cfd == nil) {
		sys->print("init: open /net/ipifc/clone: %r");
		exit;
	}
	sys->fprint(cfd, "bind ether ether0");

	server:= bootp(cfd);
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
	n := sys->mount(c.dfd, "/", sys->MREPL, "");
	if(n > 0)
		return 0;

	return -1;
}

init()
{
	spec: string;

	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if(auth != nil)
		auth->init();

	sys->print("**\n** Inferno\n** Vita Nuova\n**\n\n\n");

	#
	# Setup what we need to call a server and
	# Authenticate
	#
	sys->bind("#l", "/net", sys->MREPL);
	sys->bind("#I", "/net", sys->MAFTER);
	sys->bind("#c", "/dev", sys->MAFTER);

	sys->print("Non-volatile ram read ...\n");

	nvramfd := sys->open("#H/hd0nvram", sys->ORDWR);
	if(nvramfd != nil) {
		spec = "#Fhd0nvram";
		if(sys->bind(spec, "/nvfs", sys->MAFTER) < 0)
			sys->print("init: bind %s: %r\n", spec);
		sys->print("mounted tinyfs");
		nvramfd = nil;
	}

	sys->print("\n\n");

	if(!PROMPT) {
		if(lfs("#H/hd0fs") == 0)
			startip = 1;
		else
			bootfrom();
	} else
		bootfrom();

	sys->bind("#l", "/net", sys->MBEFORE);
	sys->bind("#I", "/net", sys->MBEFORE);
	sys->bind("#c", "/dev", sys->MBEFORE);

	if(startip)
		ipinit();

	setsysname();

	sys->print("clock...\n");
	setclock();

	if(SHELL) {
		sys->print("shell...\n");

		logon := load Logon "/dis/sh.dis";
		if(logon == nil) {
			sys->print("init: load /dis/wm/logon.dis: %r");
			exit;
		}
		dc: ref Draw->Context;
		spawn logon->init(dc, nil);
		exit;
	}

	runprogs();
}

bootfrom()
{
	buf := array[128] of byte;
	stdin := sys->fildes(0);

	fsdev := "#H/hd0disk";

	loop: for(;;) {
		sys->print("boot from [fs, net]: ");

		n := sys->read(stdin, buf, len buf);
		if(n <= 0)
			continue;
		if(buf[n-1] == byte '\n')
			n--;

		(nil, choice) := sys->tokenize(string buf[:n], "\t ");
		if(choice == nil)
			continue;

		opt := hd choice;
		choice = tl choice;

		case opt {
		* =>
			sys->print("\ninvalid boot option: '%s'\n", opt);
			break;
		"fs" or "" =>
			if(choice != nil)
				fsdev = hd choice;
			if(lfs(fsdev) == 0) {
				startip = 1;
				break loop;
			}
		"net" =>
			if(netfs() == 0)
				break loop;
		}
	}
}

runprogs()
{
	fd:= sys->open(INIT, Sys->OREAD);
	if(fd == nil) {
		sys->print("open %s: %r\n", INIT);
		return;
	}

	dc := ref Draw->Context;
	dc.ctomux = chan of int;

	for(l:=1;;l++) {
		(e, line):= getline(fd);
		if(e != nil) {
			sys->print(INIT+":%d: %s\n", l, e);
			return;
		}
		if(line == nil)
			break;
		if(line == "\n" || line[0] == '#')
			continue;
		if(line[len line-1] == '\n')
			line = line[:len line-1];
		(n, f):= sys->tokenize(line, " \t");
		if(n < 0) {
			sys->print(INIT+":%d: tokenize: %r\n", l);
			return;
		}
		if(n < 2) {
			sys->print(INIT+":%d: not enough fields\n", l);
			continue;
		}
		e = run(dc, f);
		if(e != nil)
			sys->print(INIT+":%d: %s\n", l, e);
	}
}

run(dc: ref Draw->Context, argv: list of string): string
{
	c:= hd argv;
	argv = tl argv;
	prog:= hd argv;
	ext:= ".dis";
	if(prog[len prog-4:] == ".dis")
		ext = "";
	sh:= load Sh prog+ext;
	if(sh == nil)
		sh = load Sh "/dis/"+prog+ext;
	if(sh == nil)
		return sys->sprint("%s: load: %r", prog);

	case c {
	"run" =>
		e:= ref Sys->Exception;
		if(sys->rescue("fail:*", e))
			return prog+": "+e.name;
		sh->init(dc, argv);
		return nil;
	"spawn" =>
		spawn sh->init(dc, argv);
		return nil;
	}
	return c+": unknown command";
}

getline(fd: ref Sys->FD): (string, string)
{
	s:= "";
	buf:= array[1] of byte;
	for(;;) {
		n:= sys->read(fd, buf, 1);
		if(n < 0)
			return (sys->sprint("getline: read: %r\n"), nil);
		if(n == 0)
			return (nil, s);
		s += string buf;
		if(buf[0] == byte '\n')
			return (nil, s);
	}
}

setclock()
{
	(ok, dir) := sys->stat("/");
	if (ok < 0) {
		sys->print("init: stat /: %r");
		return;
	}

	fd := sys->open("/dev/time", sys->OWRITE);
	if (fd == nil) {
		sys->print("init: open /dev/time: %r\n");
		return;
	}

	# Time is kept as microsecs, atime is in secs
	b := array of byte sys->sprint("%d000000", dir.atime);
	if (sys->write(fd, b, len b) != len b)
		sys->print("init: write /dev/time: %r");
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

bootp(cfd: ref sys->FD): string
{
	sys->print("bootp ...");

	sys->fprint(cfd, "bootp");

	fd := sys->open("/net/bootp", sys->OREAD);
	if(fd == nil) {
		sys->print("init: open /net/bootp: %r");
		exit;
	}


	buf := array[Bootpreadlen] of byte;
	nr := sys->read(fd, buf, len buf);
	fd = nil;
	if(nr <= 0) {
		sys->print("init: read /net/bootp: %r");
		exit;
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
		exit;
	}

	srv := hd ls;

	sys->print("(ip=%s)", srv);

	return srv;
}
