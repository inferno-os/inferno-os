implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "fslib.m";
	fsfilter: Fsfilter;
	fslib: Fslib;
	Report, Value, type2s, quit: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fslib;


Query: adt {
	gate: Gatechan;
	dflag: int;
	reply: chan of int;
	query: fn(q: self ref Query, d: ref Sys->Dir, name: string, depth: int): int;
};

types(): string
{
	return "xpx-d";
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
	fsfilter = load Fsfilter Fsfilter->PATH;
	if(fsfilter == nil)
		badmod(Fsfilter->PATH);
}

run(nil: ref Draw->Context, nil: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	dst := chan of (Fsdata, chan of int);
	spawn filterproc((hd tl args).x().i, dst, (hd args).p().i, opts != nil);
	return ref Value.X(dst);
}

filterproc(src, dst: Fschan, gate: Gatechan, dflag: int)
{
	fsfilter->filter(ref Query(gate, dflag, chan of int), src, dst);
	gate <-= ((nil, nil, 0), nil);
}

Query.query(q: self ref Query, d: ref Sys->Dir, name: string, depth: int): int
{
	if(depth == 0 || (q.dflag && (d.mode & Sys->DMDIR)))
		return 1;
	q.gate <-= ((d, name, depth), q.reply);
	return <-q.reply;
}
