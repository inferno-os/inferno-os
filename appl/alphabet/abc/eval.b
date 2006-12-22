implement Evalabc, Abcmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	report, Report: import reports;
include "alphabet.m";
include "alphabet/abc.m";
	abc: Abc;
	Value: import abc;

Evalabc: module {};
types(): string
{
	return "rAcs*";
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

run(nil: chan of string, r: ref Reports->Report,
		nil: list of (int, list of ref Value),
		args: list of ref Value
	): ref Value
{
	a := (hd args).A().i.alphabet;
	c := (hd tl args).c().i;
	vl, rvl: list of ref Alphabet->Value;
	for(args = tl tl args; args != nil; args = tl args)
		vl = ref (Alphabet->Value).Vs((hd args).s().i) :: vl;
	for(; vl != nil; vl = tl vl)
		rvl = hd vl :: rvl;
	vc := chan of ref Alphabet->Value;
	spawn a->eval0(c, "/status", nil, r, r.start("abceval"), rvl, vc);
	v := <-vc;
	if(v == nil)
		return nil;
	return ref Value.Vr(vr(v).i);
}

vr(v: ref Alphabet->Value): ref (Alphabet->Value).Vr
{
	pick xv := v {
	Vr =>
		return xv;
	}
	return nil;
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
