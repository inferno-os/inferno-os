implement Rewrite, Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context: import sh;
include "alphabet/reports.m";
	reports: Reports;
		report: import reports;
include "alphabet.m";
	Value: import Alphabet;

Rewrite: module {};

typesig(): string
{
	return "ccc-ds";
}

init()
{
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;
	sh->initialise();
	reports = load Reports Reports->PATH;
}

quit()
{
}

run(drawctxt: ref Draw->Context, nil: ref Reports->Report, errorc: chan of string,
		opts: list of (int, list of ref Value),
		args: list of ref Value): ref Value
{
	c := chan of ref Value;
	spawn rewriteproc(drawctxt, errorc, opts, args, c);
	return <-c;
}

# we need a separate process so that we can create a shell context
# without worrying about opening an already-opened wait file.
rewriteproc(drawctxt: ref Draw->Context, errorc: chan of string,
		opts: list of (int, list of ref Value),
		args: list of ref Value,
		c: chan of ref Value)
{
	c <-= rewrite(drawctxt, errorc, opts, args);
}

rewrite(drawctxt: ref Draw->Context, errorc: chan of string,
		opts: list of (int, list of ref Value),
		args: list of ref Value): ref Value
{
	alphabet := load Alphabet Alphabet->PATH;
	if(alphabet == nil){
		report(errorc, sys->sprint("rewrite: cannot load %q: %r", Alphabet->PATH));
		return nil;
	}
	Value: import alphabet;
	alphabet->init();
	expr := (hd args).c().i;
	decls := (hd tl args).c().i;
	ctxt := Context.new(drawctxt);
	{
		ctxt.run(w("load")::w("alphabet")::nil, 0);
		ctxt.run(c(decls) :: nil, 0);
		dstarg: list of ref Sh->Listnode;
		if(opts != nil)
			dstarg = w((hd (hd opts).t1).s().i) :: nil;
		ctxt.run(w("{x=${rewrite $1 $2}}") :: c(expr) :: dstarg, 0);
	} exception e {
	"fail:*" =>
		ctxt.run(w("clear")::nil, 0);
		report(errorc, "rewrite failed: "+e[5:]);
		return nil;
	}
	r := ctxt.get("x");
	if(len r != 2 || (hd r).cmd == nil){
		ctxt.run(w("clear")::nil, 0);
		report(errorc, "rewrite not available, strange... (len "+string len r+")");
		return nil;
	}
	ctxt.run(w("clear")::nil, 0);
	return ref Value.Vc((hd r).cmd);
}

c(c: ref Sh->Cmd): ref Sh->Listnode
{
	return ref Sh->Listnode(c, nil);
}

w(w: string): ref Sh->Listnode
{
	return ref Sh->Listnode(nil, w);
}
