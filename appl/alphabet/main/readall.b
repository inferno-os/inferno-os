implement F2s, Mainmodule;
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

F2s: module {};

typesig(): string
{
	return "sf";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
}

quit()
{
}

run(nil: ref Draw->Context, nil: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Value),
		args: list of ref Value): ref Value
{
	f := (hd args).f().i;
	fd := <-f;
	if(fd == nil){
		sys->pipe(p := array[2] of ref Sys->FD);
		f <-= p[1];
		fd = p[0];
	}
	s: string;
	buf := array[Sys->ATOMICIO] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		s += string buf[0:n];
	return ref Value.Vs(s);
}
