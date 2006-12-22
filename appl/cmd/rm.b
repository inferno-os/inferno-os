implement Rm;

include "sys.m";
	sys: Sys;
include "draw.m";

include "readdir.m";
	readdir: Readdir;

include "arg.m";

Rm: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;
quiet := 0;
force := 0;
errcount := 0;

usage()
{
	sys->fprint(stderr, "Usage: rm [-fr] file ...\n");
	raise "fail: usage";
}
allwrite := Sys->nulldir;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	allwrite.mode = 8r777 | Sys->DMDIR;

	arg := load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(stderr, "rm: can't load %s: %r\n", Arg->PATH);
		raise "fail:load";
	}
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'r' =>
			readdir = load Readdir Readdir->PATH;
			if(readdir == nil)
				sys->fprint(stderr, "rm: can't load Readdir: %r\n");	# -r is regarded as optional
		'f' =>
			quiet = 1;
		'F' =>
			force = 1;
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;
	sys->pctl(Sys->FORKNS, nil);
	for(; args != nil; args = tl args) {
		name := hd args;
		if(sys->remove(name) < 0) {
			e := sys->sprint("%r");
			(ok, d) := sys->stat(name);
			if(readdir != nil && ok >= 0 && (d.mode & Sys->DMDIR) != 0)
				rmdir(name);
			else
				err(name, e);
		}
	}
	if(errcount > 0)
		raise "fail:errors";
}

rmdir(name: string)
{
	if(force)
		sys->wstat(name, allwrite);
	(d, n) := readdir->init(name, Readdir->NONE|Readdir->COMPACT);
	for(i := 0; i < n; i++){
		path := name+"/"+d[i].name;
		if(d[i].mode & Sys->DMDIR)
			rmdir(path);
		else
			remove(path);
	}
	remove(name);
}

remove(name: string)
{
	if(sys->remove(name) < 0)
		err(name, sys->sprint("%r"));
}

err(name, e: string)
{
	if(!quiet) {
		sys->fprint(stderr, "rm: %s: %s\n", name, e);
		errcount++;
	}
}
