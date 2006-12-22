implement Ns;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "sh.m";
	sh: Sh;

ns : list of string;

Ns: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	sh = load Sh Sh->PATH;
	if (sh == nil)
		badmod(Sh->PATH);
	# sys->pctl(sys->FORKNS, nil);
	sys->unmount(nil, "/n/remote");
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);

	arg->init(argv);
	arg->setusage("ns [-v] [-r relpath] paths...");
	verbose := 0;
	relpath := "";
	while ((opt := arg->opt()) != 0) {
		case opt {
		'v' =>
			verbose = 1;
		'r' =>
			relpath = arg->earg();
			if (relpath == nil)
				arg->usage();
			if (relpath[len relpath - 1] != '/')
				relpath[len relpath] = '/';
		* =>
			arg->usage();
		}
	}

	ns = arg->argv();
	arg = nil;
	if (ns == nil) {
		sys->fprint(fdout(), "error no namespace selected\n");
		exit;
	}
	spawn buildns(relpath, verbose);
}

fdout(): ref sys->FD
{
	return sys->fildes(1);
}

buildns(relpath: string, verbose: int)
{
	# sys->pctl(sys->FORKNS, nil);
	if (sh->run(nil, "memfs"::"/n/remote"::nil) != nil) {
		sys->fprint(fdout(), "error MemFS mount failed\n");
		exit;
	}
	for (tmpl := ns; tmpl != nil; tmpl = tl tmpl) {
		nspath := hd tmpl;
		if (nspath[len nspath - 1] != '/')
			nspath[len nspath] = '/';

		bindpath := nspath;
		if (bindpath[:len relpath] == relpath) {
			bindpath = "/n/remote/"+bindpath[len relpath:];
			if (createdir(bindpath) != -1) {
				if (sys->bind(nspath, bindpath, sys->MBEFORE | sys->MCREATE) == -1) {
					if (sys->bind(nspath, bindpath, sys->MBEFORE) == -1)
						sys->fprint(fdout(), "error bind failed %s: %r\n",bindpath);
					else if (verbose)
						sys->fprint(fdout(), "data nspath %s\n", nspath);
				}
				else if (verbose)
					sys->fprint(fdout(), "data nspath %s\n", nspath);
			}
			else
				sys->fprint(fdout(), "error create failed %s\n",bindpath);
		}
	}
	spawn exportns();
}

exportns()
{
	sys->export(sys->fildes(0), "/n/remote", sys->EXPWAIT);
}

createdir(path: string): int
{
	(nil, lst) := sys->tokenize(path, "/");
	npath := "";
	for (; lst != nil; lst = tl lst) {
		(n, nil) := sys->stat(npath + "/" + hd lst);
		if (n == -1) {
			fd := sys->create(npath + "/" + hd lst, sys->OREAD, 8r777 | sys->DMDIR);
			if (fd == nil)
				return -1;
		}
		npath += "/" + hd lst;
	}
	return 0;
}

badmod(path: string)
{
	sys->fprint(fdout(), "error Ns: failed to load: %s\n",path);
	exit;
}
