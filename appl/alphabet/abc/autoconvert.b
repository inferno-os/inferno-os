implement Autoconvert, Abcmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	Cmd,
	n_BLOCK, n_WORD, n_SEQ, n_LIST, n_ADJ, n_VAR: import Sh;
include "alphabet/reports.m";
	reports: Reports;
	report: import reports;
include "alphabet.m";
include "alphabet/abc.m";
	abc: Abc;
	Value: import abc;

Autoconvert: module {};
types(): string
{
	return "AAssc";
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
	src := (hd tl args).s().i;
	dst := (hd tl tl args).s().i;
	c := (hd tl tl tl args).c().i;

	# {word} -> {(src); word $1}
	if(c.ntype == n_BLOCK && c.left.ntype == n_WORD){
		c = mk(n_BLOCK,
			mk(n_SEQ,
				mk(n_LIST, mkw(src), nil),
				mk(n_ADJ,
					c.left,
					mk(n_VAR, mkw("1"), nil)
				)
			),
			nil
		);
	}
			
	err := a->autoconvert(src, dst, c, errorc);
	if(err != nil){
		report(errorc, "abcautoconvert: "+err);
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

mk(ntype: int, left, right: ref Cmd): ref Cmd
{
	return ref Cmd(ntype, left, right, nil, nil);
}
mkw(w: string): ref Cmd
{
	return ref Cmd(n_WORD, nil, nil, w, nil);
}
