implement Typeset, Abcmodule;
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

Typeset: module {};
types(): string
{
	return "AAs";
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
		args: list of ref Value
	): ref Value
{
	a := (hd args).A().i.alphabet;
	e := a->loadtypeset((hd tl args).s().i, nil, errorc);
	if(e != nil){
		report(errorc, "typeset: "+(hd tl args).s().i+": "+e);
		return nil;
	}
	return (hd args).dup();
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
