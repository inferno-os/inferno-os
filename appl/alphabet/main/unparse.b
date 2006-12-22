implement Unparse, Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
include "alphabet/reports.m";
	reports: Reports;
		Report, report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Unparse: module {};

typesig(): string
{
	return "sc";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
	sh = load Sh Sh->PATH;
	sh->initialise();
}

quit()
{
}

run(nil: ref Draw->Context, nil: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Value),
		args: list of ref Value): ref Value
{
	return ref Value.Vs(sh->cmd2string((hd args).c().i));
}
