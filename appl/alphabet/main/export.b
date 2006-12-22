implement Export,Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
		Report, report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Export: module {};

typesig(): string
{
	return "ws";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
	reports = load Reports Reports->PATH;
}

quit()
{
}

run(nil: ref Draw->Context, r: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	w := chan of ref Sys->FD;
	addr := (hd args).s().i;
	f := chan of ref Sys->FD;
	spawn exportproc(f, (hd args).s().i, r.start("export"));
	return ref Value.Vw(f);
}

exportproc(f: chan of ref Sys->FD, dir: string, errorc: chan of string)
{
	f <-= nil;
	fd := <-f;
	if(fd == nil)
		reports->quit(errorc);
	errorc <-= nil;
	if(sys->export(fd, dir, Sys->EXPASYNC) == -1)
		report(errorc, sys->sprint("cannot export: %r"));
	reports->quit(errorc);
}
