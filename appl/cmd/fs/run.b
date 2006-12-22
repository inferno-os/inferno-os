implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context: import sh;
include "fslib.m";
	fslib: Fslib;
	Report, Value, type2s, quit: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fslib;

types(): string
{
	return "sc";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: size: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil)
		badmod(Fslib->PATH);
	sh = load Sh Sh->PATH;
	if(sh == nil)
		badmod(Sh->PATH);
	sh->initialise();
}

run(drawctxt: ref Draw->Context, nil: ref Report,
			nil: list of Option, args: list of ref Value): ref Value
{
	c := (hd args).c().i;
	ctxt := Context.new(drawctxt);
	ctxt.setlocal("s", nil);
	{
		ctxt.run(ref Sh->Listnode(c, nil)::nil, 0);
	} exception e {
	"fail:*" =>
		sys->fprint(sys->fildes(2), "fs: run: exception %q raised in %s\n", e[5:], sh->cmd2string(c));
		return nil;
	}
	sl := ctxt.get("s");
	if(sl == nil || tl sl != nil){
		sys->fprint(sys->fildes(2), "fs: run: $s has %d members; exactly one is required\n", len sl);
		return nil;
	}
	s := (hd sl).word;
	if(s == nil && (hd sl).cmd != nil)
		s = sh->cmd2string((hd sl).cmd);
	return ref Value.S(s);
}
