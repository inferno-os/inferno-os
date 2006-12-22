implement Rewrite, Abcmodule;
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

Rewrite: module {};
types(): string
{
	return "cAc-ss-rs";
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
	rtype, sig: string;
	for(; opts != nil; opts = tl opts){
		case (hd opts).t0 {
		's' =>
			sig = (hd (hd opts).t1).s().i;
		'r' =>
			rtype = (hd (hd opts).t1).s().i;
		}
	}
	a := (hd args).A().i.alphabet;
	c := (hd tl args).c().i;
	actsig: string;
	(c, actsig) = a->rewrite(c, rtype, errorc);
	if(c == nil)
		return nil;
	if(sig != nil){
		(ok, err) := a->typecompat(sig, actsig);
		if(err != nil){
			report(errorc, "rewrite: "+err);
			return nil;
		}
		if(ok == 0){
			report(errorc, sys->sprint("rewrite: %q is not compatible with %q", sig, actsig));
			return nil;
		}
	}
	return ref Value.Vc(c);
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
