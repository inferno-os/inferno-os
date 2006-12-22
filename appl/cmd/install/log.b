implement Fsmodule;

include "sys.m";
	sys: Sys;

include "draw.m";

include "sh.m";

include "daytime.m";
	daytime: Daytime;

include "fslib.m";
	fslib: Fslib;
	Report, Value, type2s, quit: import fslib;
	Fschan, Fsdata, Entrychan, Entry,
	Gatechan, Gatequery, Nilentry, Option,
	Next, Down, Skip, Quit: import Fslib;

types(): string
{
	return "vt-us-gs";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: log: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fslib = load Fslib Fslib->PATH;
	if(fslib == nil)
		badmod(Fslib->PATH);
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		badmod(Daytime->PATH);
}

run(nil: ref Draw->Context, report: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	uid, gid: string;
	for(; opts != nil; opts = tl opts){
		o := hd (hd opts).args;
		case (hd opts).opt {
		'u' =>	uid = o.s().i;
		'g' =>	gid = o.s().i;
		}
	}
	sync := chan of int;
	spawn logproc(sync, (hd args).t().i, report.start("log"), uid, gid);
	return ref Value.V(sync);
}

logproc(sync: chan of int, c: Entrychan, errorc: chan of string, uid: string, gid: string)
{
	if(<-sync == 0){
		c.sync <-= 0;
		quit(errorc);
		exit;
	}
	c.sync <-= 1;

	now := daytime->now();
	for(seq := 0; ((d, p, nil) := <-c.c).t0 != nil; seq++){
		if(uid != nil)
			d.uid = uid;
		if(gid != nil)
			d.gid = gid;
		sys->print("%ud %ud %c %q - - %uo %q %q %ud %bd%s\n", now, seq, 'a', p, d.mode, d.uid, d.gid, d.mtime, d.length, "");
	}
	quit(errorc);
}
