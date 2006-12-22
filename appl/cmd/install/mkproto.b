#	
# Copyright © 2000 Vita Nuova (Holdings) Limited.  All rights reserved.	
#

implement Mkproto;

# make a proto description of the directory or file

include "sys.m";
	sys: Sys;

include "draw.m";

include "readdir.m";
	readdir: Readdir;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Mkproto: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "Usage: mkproto [ file|directory ... ]\n");
	raise "fail:usage";
}

not: list of string;
bout: ref Iobuf;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	readdir = load Readdir Readdir->PATH;
	bufio = load Bufio Bufio->PATH;

	bout = bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	argv = tl argv;
	while (argv != nil && hd argv != nil && (hd argv)[0] == '-') {
		not = (hd argv)[1:] :: not;
		argv = tl argv;
	}
	if (argv == nil)
		visit(".", nil, -1);
	else if (tl argv == nil)
		visit(hd argv, nil, -1);
	else {
		for ( ; argv != nil; argv = tl argv)
			visit(hd argv, hd argv, 0);
	}
	bout.flush();
}

warn(s: string)
{
	sys->fprint(sys->fildes(2), "mkproto: %s\n", s);
}

visit(fulln: string, reln: string, depth: int)
{
	if (depth == 0) {
		for (n := not; n != nil; n = tl n) {
			if (hd n == reln) {
				# sys->fprint(stderr, "skipping %s\n", reln);
				return;
			}
		}
		# sys->fprint(stderr, "doing %s\n", reln);
	}
	(ok, d) := sys->stat(fulln);
	if(ok < 0){
		warn(sys->sprint("cannot stat %s: %r", fulln));
		return;
	}
	if (depth >= 0)
		visitf(fulln, reln, d, depth);
	if (d.mode & Sys->DMDIR)
		visitd(fulln, reln, d, depth);
}

visitd(fulln: string, nil: string, nil: Sys->Dir, depth: int)
{
	(dir, n) := readdir->init(fulln, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		path := "/"+dir[i].name;
		visit(fulln+path, dir[i].name, depth+1);
	}
}

visitf(nil: string, reln: string, nil: Sys->Dir, depth: int)
{
	for (i := 0; i < depth; i++)
		bout.putc('\t');
	bout.puts(sys->sprint("%q\n", reln));
}
