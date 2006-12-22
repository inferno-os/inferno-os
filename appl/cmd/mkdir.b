implement Mkdir;

include "sys.m";
	sys: Sys;

include "draw.m";


stderr: ref Sys->FD;

Mkdir: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	if(argv == nil || (argv = tl argv) == nil)
		exit;
	pflag := 0;
	if(hd argv == "-p"){
		pflag = 1;
		argv = tl argv;
	}
	e := "";
	for(; argv != nil; argv = tl argv){
		dir := hd argv;
		if(!pflag){
			(ok, d) := sys->stat(dir);
			if(ok < 0){
				if(mkdir(dir) < 0)
					e = "error";
			}else{
				sys->fprint(stderr, "mkdir: %s already exists\n", dir);
				e = "error";
			}
		}else if(mkpath(dir) < 0)
			e = "error";
	}
	if(e != nil)
		raise "fail:"+e;
}

mkpath(dir: string): int
{
	(nil, flds) := sys->tokenize(dir, "/");
	s := "";
	if(dir != "" && dir[0] != '/')
		s = ".";
	for(; flds != nil; flds = tl flds){
		s += "/"+hd flds;
		(ok, d) := sys->stat(s);
		if(ok < 0){
			if(mkdir(s) < 0)
				return -1;
		}else if((d.mode & Sys->DMDIR) == 0){
			sys->fprint(stderr, "mkdir: can't create %s: %s not a directory\n", dir, s);
			return -1;
		}
	}
	return 0;
}

mkdir(dir: string): int
{
	f := sys->create(dir, Sys->OREAD, Sys->DMDIR + 8r777);
	if(f == nil) {
		sys->fprint(stderr, "mkdir: can't create %s: %r\n", dir);
		return -1;
	}
	return 0;
}
