implement Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
		Report, report, quit: import reports;
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

typesig(): string
{
	return "fs";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
	reports = load Reports Reports->PATH;
}

run(nil: ref Draw->Context, r: ref Reports->Report, errorc: chan of string,
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	f := chan of ref Sys->FD;
	file := (hd args).s().i;
	if((fd0 := sys->open(file, Sys->OREAD)) == nil){
		report(errorc, sys->sprint("cannot open %q: %r", file));
		return nil;
	}
	spawn readproc(f, fd0, r.start("read"));
	return ref Value.F(f);
}

readproc(f: chan of ref Sys->FD, fd0: ref Sys->FD, errorc: chan of string)
{
	f <-= fd0;
	fd1 := <-f;
	if(fd1 == nil)
		quit(errorc);
	buf := array[8192] of byte;
	while((n := sys->read(fd0, buf, len buf)) > 0)
		sys->write(fd1, buf, n);
	sys->write(fd1, array[0] of byte, 0);
	quit(errorc);
}
