implement Print,Mainmodule;
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

Print: module {};

typesig(): string
{
	return "rfs";
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

run(nil: ref Draw->Context, nil: ref Reports->Report, errorc: chan of string,
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	r := chan of string;
	fd := sys->fildes(int (hd tl args).s().i);
	if(fd == nil){
		report(errorc, sys->sprint("error: no such fd %q", (hd tl args).s().i));
		return nil;
	}
	spawn printproc(r, (hd args).f().i, fd);
	return ref Value.Vr(r);
}

printproc(r: chan of string, f: chan of ref Sys->FD, fd: ref Sys->FD)
{
	if(<-r != nil){
		<-f;
		f <-= nil;
		exit;
	}
	<-f;
	f <-= fd;
	r <-= nil;
}
