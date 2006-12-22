implement Declare, Abcmodule;
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

Declare: module {};
types(): string
{
	return "AAss*-q-c";
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
		opts: list of (int, list of ref Value),
		args: list of ref Value
	): ref Value
{
	flags := 0;
	for(; opts != nil; opts = tl opts){
		case (hd opts).t0 {
		'q' =>
			flags |= Alphabet->ONDEMAND;
		'c' =>
			flags |= Alphabet->CHECK;
		}
	}

	n := len args;
	if(n > 3){
		report(errorc, "declare: maximum of two arguments allowed");
		return nil;
	}
	a := (hd args).A().i.alphabet;
	m := (hd tl args).s().i;
	sig := "";
	if(n > 2)
		sig = (hd tl tl args).s().i;
	e := a->declare(m, sig, flags);
	if(e != nil){
		report(errorc, "declare: "+e);
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
