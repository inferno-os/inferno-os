implement Touch;

include "sys.m";
	sys: Sys;

include "draw.m";

include "daytime.m";
	daytime: Daytime;

include "arg.m";

stderr: ref Sys->FD;

Touch: module
{
	init: fn(ctxt: ref Draw->Context, argl: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	force := 1;
	status := 0;
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		cantload(Daytime->PATH);
	arg := load Arg Arg->PATH;
	if(arg == nil)
		cantload(Arg->PATH);
	arg->init(args);
	arg->setusage("touch [-c] [-t time] file ...");
	now := daytime->now();
	while((c := arg->opt()) != 0)
		case c {
		't' =>		now = int arg->earg();
		'c' =>	force = 0;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;
	for(; args != nil; args = tl args)
		status += touch(force, hd args, now);
	if(status)
		raise "fail:touch";
}

cantload(s: string)
{
	sys->fprint(stderr, "touch: can't load %s: %r\n", s);
	raise "fail:load";
}

touch(force: int, name: string, now: int): int
{
	dir := sys->nulldir;
	dir.mtime = now;
	(rc, nil) := sys->stat(name);
	if(rc >= 0){
		if(sys->wstat(name, dir) >= 0)
			return 0;
		force = 0;	# we don't want to create it: it's there, we just can't wstat it
	}
	if(force == 0) {
		sys->fprint(stderr, "touch: %s: cannot change time: %r\n", name);
		return 1;
	}
	if((fd := sys->create(name, Sys->OREAD|Sys->OEXCL, 8r666)) == nil) {
		sys->fprint(stderr, "touch: %s: cannot create: %r\n", name);
		return 1;
	}
	sys->fwstat(fd, dir);
	return 0;
}
