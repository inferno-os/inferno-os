implement Install;

#
# Determine which packages need installing and calls install/inst 
# to actually install each one
#

# usage: install/install -d -F -g -s -u -i installdir -p platform -r root -P package

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "arg.m";
	arg: Arg;
include "readdir.m";
	readdir : Readdir;
include "sh.m";

Install: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# required dirs, usually in the standard inferno root.
# The network download doesn't include them because of
# problems with versions of tar that won't create empty dirs
# so we'll make sure they exist.

reqdirs := array [] of {
	"/mnt",
	"/mnt/wrap",
	"/n",
	"/n/remote",
	"/tmp",
};

YES, NO, QUIT, ERR : con iota;
INST : con "install/inst";	# actual install program
MTPT : con "/n/remote";	# mount point for user's inferno root

debug := 0;
force := 0;
exitemu := 0;
uflag := 0;
stderr : ref Sys->FD;
installdir := "/install";
platform := "Plan9";
lcplatform : string;
root := "/usr/inferno";
local: int;
global: int = 1;
waitfd : ref Sys->FD;

Product : adt {
	name : string;
	pkgs : ref Package;
	nxt : ref Product;
};

Package : adt {
	name : string;
	nxt : ref Package;
};

instprods : ref Product;	# products/packages already installed

# platform independent packages
xpkgs := array[] of { "inferno", "utils", "src", "ipaq", "minitel", "sds" };
ypkgs: list of string;
		
init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	# Hack for network download...
	# make sure the dirs we need exist
	for (dirix := 0; dirix < len reqdirs; dirix++) {
		dir := reqdirs[dirix];
		(exists, nil) := sys->stat(dir);
		if (exists == -1) {
			fd := sys->create(dir, Sys->OREAD, Sys->DMDIR + 8r7775);
			if (fd == nil)
				fatal(sys->sprint("cannot create directory %s: %r\n", dir));
			fd = nil;
		}
	}

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		fatal(sys->sprint("cannot load %s: %r\n", Bufio->PATH));
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		fatal(sys->sprint("cannot load %s: %r\n", Readdir->PATH));
	str = load String String->PATH;
	if(str == nil)
		fatal(sys->sprint("cannot load %s: %r\n", String->PATH));
	arg = load Arg Arg->PATH;
	if(arg == nil)
		fatal(sys->sprint("cannot load %s: %r\n", Arg->PATH));
	arg->init(args);
	while((c := arg->opt()) != 0) {
		case c {
			'd' =>
				debug = 1;
			'F' =>
				force = 1;
			's' =>
				exitemu = 1;
			'i' => 
				installdir = arg->arg();
				if (installdir == nil)
					fatal("install directory missing");
			'p' =>
				platform = arg->arg();
				if (platform == nil)
					fatal("platform missing");
			'P' =>
				pkg := arg->arg();
				if (pkg == nil)
					fatal("package missing");
				ypkgs = pkg :: ypkgs;
			'r' =>
				root = arg->arg();
				if (root == nil)
					fatal("inferno root missing");
			'u' =>
				uflag = 1;
			'g' =>
				global = 0;
			'*' =>
				usage();
		}
	}
	if (arg->argv() != nil)
		usage();
	lcplatform = str->tolower(platform);
	(ok, dir) := sys->stat(installdir);
	if (ok < 0)
		fatal(sys->sprint("cannot open install directory %s", installdir));
	nt := lcplatform == "nt";
	if (nt) {
		# root os of the form ?:/.........
		if (len root < 3 || root[1] != ':' || root[2] != '/')
			fatal(sys->sprint("root %s not of the form ?:/.......", root));
		spec := root[0:2];
		root = root[2:];
		if (sys->bind("#U"+spec, MTPT, Sys->MREPL|Sys->MCREATE) < 0)
			fatal(sys->sprint("cannot bind to drive %s", spec));
	}
	else {
		if (root[0] != '/')
			fatal(sys->sprint("root %s must be an absolute path name", root));
		if (sys->bind("#U*", MTPT, Sys->MREPL|Sys->MCREATE) < 0)
			fatal("cannot bind to system root");
	}
	(ok, dir) = sys->stat(MTPT+root);
	if (ok >= 0) {
		if ((dir.mode & Sys->DMDIR) == 0)
			fatal(sys->sprint("inferno root %s is not a directory", root));
	}
	else if (sys->create(MTPT+root, Sys->OREAD, 8r775 | Sys->DMDIR) == nil)
		fatal(sys->sprint("cannot create inferno root %s: %r", root));
	# need a writable tmp directory /tmp in case installing from CD
	(ok, dir) = sys->stat(MTPT+root+"/tmp");
	if (ok >= 0) {
		if ((dir.mode & Sys->DMDIR) == 0)
			fatal(sys->sprint("inferno root tmp %s is not a directory", root+"/tmp"));
	}
	else if (sys->create(MTPT+root+"/tmp", Sys->OREAD, 8r775 | Sys->DMDIR) == nil)
		fatal(sys->sprint("cannot create inferno root tmp %s: %r", root+"/tmp"));
	if (sys->bind(MTPT+root, MTPT, Sys->MREPL | Sys->MCREATE) < 0)
		fatal("cannot bind inferno root");
	if (sys->bind(MTPT+"/tmp", "/tmp", Sys->MREPL | Sys->MCREATE) < 0)
		fatal("cannot bind inferno root tmp");
	root = MTPT;
	
	if (nt || 1)
		local = 1;
	else {
		sys->print("You can either install software specific to %s only or\n", platform);
		sys->print(" install software for all platforms that we support.\n");
		sys->print("If you are unsure what to do, answer yes to the question following.\n");
		sys->print(" You can install the remainder of the software at a later date if desired.\n");
		sys->print("\n");
		b := bufio->fopen(sys->fildes(0), Bufio->OREAD);
		if (b == nil)
			fatal("cannot open stdin");
		for (;;) {
			sys->print("Install software specific to %s only ? (yes/no/quit) ", platform);
			resp := getresponse(b);
			ans := answer(resp);
			if (ans == QUIT)
				exit;
			else if (ans == ERR)
				sys->print("bad response %s\n\n", resp);
			else {
				local = ans == YES;
				break;
			}
		}
	}
	instprods = dowraps(root+"/wrap");
	doprods(installdir);
	if (!nt)
		sys->print("installation complete\n");
	if (exitemu)
		shutdown();
}

getresponse(b : ref Iobuf) : string
{
	s := b.gets('\n');
	while (s != nil && (s[0] == ' ' || s[0] == '\t'))
		s = s[1:];
	while (s != nil && ((c := s[len s - 1]) == ' ' || c == '\t' || c == '\n'))
		s = s[0: len s - 1];
	return s;
}

answer(s : string) : int
{
	s = str->tolower(s);
	if (s == "y" || s == "yes")
		return YES;
	if (s == "n" || s == "no")
		return NO;
	if (s == "q" || s == "quit")
		return QUIT;
	return ERR;
}

usage()
{
	fatal("Usage: install [-d] [-F] [-s] [-u] [-i installdir ] [-p platform ] [-r root]");
}

fatal(s : string)
{
	sys->fprint(stderr, "install: %s\n", s);
	exit;
}

dowraps(d : string) : ref Product
{
	p : ref Product;

	# make an inventory of what is already apparently installed
	(dir, n) := readdir->init(d, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		if (dir[i].mode & Sys->DMDIR) {
			p = ref Product(str->tolower(dir[i].name), nil, p);
			p.pkgs = dowrap(d + "/" + dir[i].name);
		}
	}
	return p;
}

dowrap(d : string) : ref Package
{
	p : ref Package;

	(dir, n) := readdir->init(d, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++)
		p = ref Package(dir[i].name, p);
	return p;
}
	
doprods(d : string)
{
	(dir, n) := readdir->init(d, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		if (dir[i].mode & Sys->DMDIR)
			doprod(str->tolower(dir[i].name), d + "/" + dir[i].name);
	}
}

doprod(pr : string, d : string)
{
	# base package, updates and update packages have the name
	# <timestamp> or <timestamp.gz>
	if (!wanted(pr))
		return;
	(dir, n) := readdir->init(d, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		pk := dir[i].name;
		l := len pk;
		if (l >= 4 && pk[l-3:l] == ".gz")
			pk = pk[0:l-3];
		else if (l >= 5 && (pk[l-4:] == ".tgz" || pk[l-4:] == ".9gz"))
			pk = pk[0:l-4];
		dopkg(pk, pr, d+"/"+dir[i].name);
		
	}
}

dopkg(pk : string, pr : string, d : string)
{
	if (!installed(pk, pr))
		install(d);
}

installed(pkg : string, prd : string) : int
{
	for (pr := instprods; pr != nil; pr = pr.nxt) {
		if (pr.name == prd) {
			for (pk := pr.pkgs; pk != nil; pk = pk.nxt) {
				if (pk.name == pkg)
					return 1;
			}
			return 0;
		}
	}
	return 0;
}

lookup(pr : string) : int
{
	for (i := 0; i < len xpkgs; i++) {
		if (xpkgs[i] == pr)
			return i;
	}
	return -1;
}

plookup(pr: string): int
{
	for(ps := ypkgs; ps != nil; ps = tl ps)
		if(pr == hd ps)
			return 1;
	return 0;
}

wanted(pr : string) : int
{
	if (!local || global)
		return 1;
	if(ypkgs != nil)	# overrides everything else
		return plookup(pr);
	found := lookup(pr);
	if (found >= 0)
		return 1;
	return pr == lcplatform || prefix(lcplatform, pr);
}

install(d : string)
{
	if (waitfd == nil)
		waitfd = openwait(sys->pctl(0, nil));
	sys->fprint(stderr, "installing package %s\n", d);
	if (debug)
		return;
	c := chan of int;
	args := "-t" :: "-v" :: "-r" :: root :: d :: nil;
	if (uflag)
		args = "-u" :: args;
	if (force)
		args = "-F" :: args;
	spawn exec(INST, INST :: args, c);
	execpid := <- c;
	wait(waitfd, execpid);
}

exec(cmd : string, argl : list of string, ci : chan of int)
{
	ci <-= sys->pctl(Sys->FORKNS|Sys->NEWFD|Sys->NEWPGRP, 0 :: 1 :: 2 :: stderr.fd :: nil);
	file := cmd;
	if(len file<4 || file[len file-4:] !=".dis")
		file += ".dis";
	c := load Command file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(file[0] !='/' && file[0:2] !="./") {
			c = load Command "/dis/"+file; 
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil)
			fatal(sys->sprint("%s: %s\n", cmd, err));
	}
	c->init(nil, argl);
}

openwait(pid : int) : ref Sys->FD
{
	w := sys->sprint("#p/%d/wait", pid);
	fd := sys->open(w, Sys->OREAD);
	if (fd == nil)
		fatal("fd == nil in wait");
	return fd;
}
	
wait(wfd : ref Sys->FD, wpid : int)
{
	n : int;

	buf := array[Sys->WAITLEN] of byte;
	status := "";
	for(;;) {
		if ((n = sys->read(wfd, buf, len buf)) < 0)
			fatal("bad read in wait");
		status = string buf[0:n];
		break;
	}
	if (int status != wpid)
		fatal("bad status in wait");
	if(status[len status - 1] != ':')
		fatal(sys->sprint("%s\n", status));
}

shutdown()
{
	fd := sys->open("/dev/sysctl", sys->OWRITE);
	if(fd == nil)
		fatal("cannot shutdown emu");
	if (sys->write(fd, array of byte "halt", 4) < 0)
		fatal(sys->sprint("shutdown: write failed: %r\n"));
}

prefix(s, t : string) : int
{
	if (len s <= len t)
		return t[0:len s] == s;
	return 0;
}
