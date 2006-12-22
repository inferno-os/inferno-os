implement Fsmodule;
include "sys.m";
	sys: Sys;
include "daytime.m";
	daytime: Daytime;
include "draw.m";
include "sh.m";
include "fslib.m";
	fslib: Fslib;
	Option, Value, Entrychan, Report: import fslib;

types(): string
{
	return "vt-u-m";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: ls: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil)
		badmod(Fslib->PATH);
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		badmod(Daytime->PATH);
}

run(nil: ref Draw->Context, report: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	sync := chan of int;
	spawn lsproc(sync, opts, (hd args).t().i, daytime, report.start("ls"));
	return ref Value.V(sync);
}

lsproc(sync: chan of int, opts: list of Option, c: Entrychan, daytime: Daytime, errorc: chan of string)
{
	now := daytime->now();
	mflag := uflag := 0;
	if(<-sync == 0){
		c.sync <-= 0;
		errorc <-= nil;
	}
	c.sync <-= 1;
	for(; opts != nil; opts = tl opts){
		case (hd opts).opt {
		'm' =>
			mflag = 1;
		'u' =>
			uflag = 1;
		}
	}
	while(((dir, p, nil) := <-c.c).t0 != nil){
		t := dir.mtime;
		if(uflag)
			t = dir.atime;
		s := sys->sprint("%s %c %d %s %s %bud %s %s\n",
			modes(dir.mode), dir.dtype, dir.dev,
			dir.uid, dir.gid, dir.length,
			daytime->filet(now, dir.mtime), p);
		if(mflag)
			s = "[" + dir.muid + "] " + s;
		sys->print("%s", s);
	}
	errorc <-= nil;
}

mtab := array[] of {
	"---",	"--x",	"-w-",	"-wx",
	"r--",	"r-x",	"rw-",	"rwx"
};

modes(mode: int): string
{
	s: string;

	if(mode & Sys->DMDIR)
		s = "d";
	else if(mode & Sys->DMAPPEND)
		s = "a";
	else if(mode & Sys->DMAUTH)
		s = "A";
	else
		s = "-";
	if(mode & Sys->DMEXCL)
		s += "l";
	else
		s += "-";
	s += mtab[(mode>>6)&7]+mtab[(mode>>3)&7]+mtab[mode&7];
	return s;
}
