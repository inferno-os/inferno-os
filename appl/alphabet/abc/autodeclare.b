implement Autoconvert, Abcmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
include "alphabet.m";
include "alphabet/abc.m";
	abc: Abc;
	Value: import abc;

Autoconvert: module {};
types(): string
{
	return "AAs";
}

init()
{
	abc = checkload(load Abc Abc->PATH, Abc->PATH);
	abc->init();
}

quit()
{
}

run(nil: chan of string, nil: ref Reports->Report,
		nil: list of (int, list of ref Value),
		args: list of ref Value
	): ref Value
{
	(hd args).A().i.alphabet->setautodeclare(int (hd tl args).s().i);
	return (hd args).dup();
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
