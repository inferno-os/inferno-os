implement Mkabc, Abcmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	report: import reports;
include "alphabet.m";
include "alphabet/abc.m";
	abc: Abc;
	Value: import abc;

Mkabc: module {};
types(): string
{
	return "A";
}

init()
{
	sys = load Sys Sys->PATH;
	reports = checkload(load Reports Reports->PATH, Reports->PATH);
	abc = checkload(load Abc Abc->PATH, Abc->PATH);
	abc->init();
}

quit()
{
}

run(errorc: chan of string, nil: ref Reports->Report,
		nil: list of (int, list of ref Value),
		nil: list of ref Value
	): ref Value
{
	alphabet := load Alphabet Alphabet->PATH;
	if(alphabet == nil){
		report(errorc, sys->sprint("abc: cannot load %q: %r", Alphabet->PATH));
		return nil;
	}
	alphabet->init();
	c := chan[1] of int;
	c <-= 1;
	return ref Value.VA((c, alphabet));
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
