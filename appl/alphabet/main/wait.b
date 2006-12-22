implement Wait, Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Wait: module {};

typesig(): string
{
	return "sr";
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
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	r := (hd args).r().i;
	r <-= nil;
	return ref Value.Vs(<-r);
}
