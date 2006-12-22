implement Declares, Abcmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	n_BLOCK, n_ADJ, n_VAR, n_WORD: import Sh;
include "alphabet/reports.m";
	reports: Reports;
	report, Report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
include "alphabet/abc.m";
	abc: Abc;
	Value: import abc;
include "alphabet/abctypes.m";
	abctypes: Abctypes;
	Abccvt: import abctypes;

cvt: ref Abccvt;

types(): string
{
	return "AAc";
}

init()
{
	sys = load Sys Sys->PATH;
	reports = checkload(load Reports Reports->PATH, Reports->PATH);
	abc = checkload(load Abc Abc->PATH, Abc->PATH);
	abc->init();
	alphabet = checkload(load Alphabet Alphabet->PATH, Alphabet->PATH);
	alphabet->init();
	abctypes = checkload(load Abctypes Abctypes->PATH, Abctypes->PATH);
	(c, nil, abccvt) := abctypes->proxy0();
	cvt = abccvt;
	alphabet->loadtypeset("/abc", c, nil);
	alphabet->importtype("/abc/abc");
	alphabet->importtype("/string");
	alphabet->importtype("/cmd");
	c = nil;
	# note: it's faster if we provide the signatures, as we don't
	# have to load the module to find out its signature just to throw
	# it away again. pity about the maintenance.

	# Edit x s:(/abc/[a-z]+) (.*):declimport("\1", "\2");
	declimport("/abc/autoconvert", "abc string string cmd -> abc");
	declimport("/abc/autodeclare", "abc string -> abc");
	declimport("/abc/declare", "[-qc] abc string [string...] -> abc");
	declimport("/abc/define", "abc string cmd -> abc");
	declimport("/abc/import", "abc string [string...] -> abc");
	declimport("/abc/type", "abc string [string...] -> abc");
	declimport("/abc/typeset", "abc string -> abc");
	declimport("/abc/undeclare", "abc string [string...] -> abc");
}

quit()
{
	alphabet->quit();
}

run(errorc: chan of string, r: ref Reports->Report,
		nil: list of (int, list of ref Value),
		args: list of ref Value
	): ref Value
{
	(av, err) := alphabet->importvalue(cvt.int2ext((hd args).dup()), "/abc/abc");
	if(av == nil){
		report(errorc, sys->sprint("declares: cannot import abc value: %s", err));
		return nil;
	}
	vc := chan of ref Alphabet->Value;
	spawn alphabet->eval0((hd tl args).c().i, "/abc/abc", nil, r, r.start("evaldecl"), av :: nil, vc);
	av = <-vc;
	if(av == nil)
		return nil;
	v := cvt.ext2int(av).dup();
	alphabet->av.free(1);
	return v;
}

declimport(m: string, sig: string)
{
	if((e := alphabet->declare(m, sig, Alphabet->ONDEMAND)) != nil)
		raise sys->sprint("fail:cannot declare %s: %s", m, e);
	alphabet->importmodule(m);
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}

declares(a: Alphabet, decls: ref Sh->Cmd, errorc: chan of string, stopc: chan of int): string
{
	spawn reports->reportproc(reportc := chan of string, stopc, reply := chan of ref Report);
	r := <-reply;
	reply = nil;
	spawn declaresproc(a, decls, r.start("declares"), r, vc := chan of ref Value);
	r.enable();

	v: ref Value;
wait:
	for(;;)alt{
	v = <-vc =>
		;
	msg := <-reportc =>
		if(msg == nil)
			break wait;
		errorc <-= sys->sprint("declares: %s", msg);
	}
	if(v == nil)
		return "declarations failed";
	return nil;
}

declaresproc(a: Alphabet, decls: ref Sh->Cmd, errorc: chan of string, r: ref Report, vc: chan of ref Value)
{
	novals: list of ref Value;
	vc <-= run(errorc, r, nil, abc->mkabc(a).dup() :: ref Value.Vc(decls) :: novals);
	errorc <-= nil;
}
