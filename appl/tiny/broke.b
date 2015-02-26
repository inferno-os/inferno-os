implement Broke;

include "sys.m";
	sys: Sys;
include "draw.m";

Broke: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	fd := sys->open("/prog", Sys->OREAD);
	if(fd == nil)
		err(sys->sprint("can't open /prog: %r"));
	killed := "";
	for(;;){
		(n, dir) := sys->dirread(fd);
		if(n <= 0){
			if(n < 0)
				err(sys->sprint("error reading /prog: %r"));
			break;
		}
		for(i := 0; i < n; i++)
			if(isbroken(dir[i].name) && kill(dir[i].name))
				killed += sys->sprint(" %s", dir[i].name);
	}
	if(killed != nil)
		sys->print("%s\n", killed);
}

isbroken(pid: string): int
{
	statf := "/prog/" + pid + "/status";
	fd := sys->open(statf, Sys->OREAD);
	if (fd == nil)
		return 0;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if (n < 0) {	# process died or is exiting
		# sys->fprint(stderr(), "broke: can't read %s: %r\n", statf);
		return 0;
	}
	(nf, l) := sys->tokenize(string buf[0:n], " ");
	return nf >= 5 && hd tl tl tl tl l == "broken";
}

kill(pid: string): int
{
	ctl := "/prog/" + pid + "/ctl";
	fd := sys->open(ctl, sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "kill") < 0){
		sys->fprint(stderr(), "broke: can't kill %s: %r\n", pid);	# but press on
		return 0;
	}
	return 1;
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "broke: %s\n", s);
	raise "fail:error";
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
