implement Parse, Mainmodule;
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

Parse: module {};

typesig(): string
{
	return "cs";
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

run(nil: ref Draw->Context, nil: ref Reports->Report, errorc: chan of string,
		nil: list of (int, list of ref Value),
		args: list of ref Value): ref Value
{
	(c, err) := sh->parse((hd args).s().i);
	if(c == nil){
		report(errorc, sys->sprint("parse: parse %q failed: %s", (hd args).s().i, err));
		return nil;
	}
	return ref Value.Vc(c);
}
