implement Print, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	Report: import reports;
include "alphabet/fs.m";
	fs: Fs;
	Value: import fs;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fs;

Print: module {};

types(): string
{
	return "ft";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	reports = load Reports Reports->PATH;
	if(reports == nil)
		badmod(Reports->PATH);
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Fs->PATH);
	fs->init();
}

run(nil: ref Draw->Context, report: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	f := chan of ref Sys->FD;
	spawn printproc(f, (hd args).t().i, report.start("/fs/print"));
	return ref Value.Vf(f);
}

printproc(f: chan of ref Sys->FD, c: Entrychan, errorc: chan of string)
{
	f <-= nil;
	if((fd := <-f) == nil){
		c.sync <-= 0;
		reports->quit(errorc);
	}
	c.sync <-= 1;
	while(((d, p, nil) := <-c.c).t0 != nil)
		sys->fprint(fd, "%s\n", p);
	sys->fprint(fd, "");
	reports->quit(errorc);
}
