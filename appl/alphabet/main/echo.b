implement Echo, Mainmodule;
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

Echo: module {};

typesig(): string
{
	return "fs-n";
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

run(nil: ref Draw->Context, nil: ref Reports->Report, nil: chan of string,
		opts: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	f := chan of ref Sys->FD;
	s := (hd args).s().i;
	if(opts == nil)
		s[len s] = '\n';
	spawn echoproc(f, s);
	return ref Value.Vf(f);
}

echoproc(f: chan of ref Sys->FD, s: string)
{
	f <-= nil;
	fd := <-f;
	if(fd == nil)
		exit;
	sys->fprint(fd, "%s", s);
	sys->write(fd, array[0] of byte, 0);
}
