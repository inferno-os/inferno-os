implement Create,Mainmodule;
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

Create: module {};

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
	fd := sys->create((hd tl args).s().i, Sys->OWRITE, 8r666);
	if(fd == nil){
		report(errorc, sys->sprint("error: cannot create %q: %r", (hd tl args).s().i));
		return nil;
	}
	spawn createproc(r, (hd args).f().i, fd);
	return ref Value.Vr(r);
}

createproc(r: chan of string, f: chan of ref Sys->FD, fd: ref Sys->FD)
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
