implement Ls, Fsmodule;
include "sys.m";
	sys: Sys;
include "daytime.m";
	daytime: Daytime;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	Report: import reports;
include "alphabet/fs.m";
	fs: Fs;
	Option, Value, Entrychan: import fs;

Ls: module {};

types(): string
{
	return "ft-u-m";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: ls: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fs = load Fs Fs->PATH;
	reports = load Reports Reports->PATH;
	if(reports == nil)
		badmod(Reports->PATH);
	if(fs == nil)
		badmod(Fs->PATH);
	fs->init();
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		badmod(Daytime->PATH);
}

run(nil: ref Draw->Context, report: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	f := chan of ref Sys->FD;
	spawn lsproc(f, opts, (hd args).t().i, report.start("/fs/ls"));
	return ref Value.Vf(f);
}

lsproc(f: chan of ref Sys->FD, opts: list of Option, c: Entrychan, errorc: chan of string)
{
	f <-= nil;
	if((fd := <-f) == nil){
		c.sync <-= 0;
		reports->quit(errorc);
	}
	now := daytime->now();
	mflag := uflag := 0;
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
		sys->fprint(fd, "%s", s);
	}
	reports->quit(errorc);
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
