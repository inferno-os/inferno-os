implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context: import sh;
include "fslib.m";
	fslib: Fslib;
	Option, Value, Gatechan, Gatequery, Report, Nilentry: import fslib;

types(): string
{
	return "pc-p-P";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: query: cannot load %s: %r\n", p);
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
}

run(drawctxt: ref Draw->Context, nil: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	pflag := 0;
	for(; opts != nil; opts = tl opts){
		o := hd opts;
		case o.opt {
		'p' =>
			pflag = 1;
		'P' =>
			pflag = 2;
		}
	}

	v := ref Value.P(chan of Gatequery);
	spawn querygate(drawctxt, v.i, (hd args).c().i, pflag);
	v.i <-= (Nilentry, nil);
	return v;
}

querygate(drawctxt: ref Draw->Context, c: Gatechan, cmd: ref Sh->Cmd, pflag: int)
{
	sys->pctl(Sys->NEWFD, 0::1::2::nil);
	ctxt := Context.new(drawctxt);
	<-c;
	argv := ref Sh->Listnode(cmd, nil) :: nil;
	while((((d, p, nil), reply) := <-c).t0.t0 != nil){
		ctxt.set("file", ref Sh->Listnode(nil, p) :: nil);
		if(pflag)
			setstatenv(ctxt, d, pflag);
		err := "";
		{
			err = ctxt.run(argv, 0);
		} exception e {
		"fail:*" =>
			err = e;
		}
		reply <-= (err == nil);
	}
}

# XXX shouldn't duplicate this...

setenv(ctxt: ref Context, var: string, val: list of string)
{
	ctxt.set(var, sh->stringlist2list(val));
}

setstatenv(ctxt: ref Context, dir: ref Sys->Dir, pflag: int)
{
	setenv(ctxt, "mode", modes(dir.mode) :: nil);
	setenv(ctxt, "uid", dir.uid :: nil);
	setenv(ctxt, "mtime", string dir.mtime :: nil);
	setenv(ctxt, "length", string dir.length :: nil);

	if(pflag > 1){
		setenv(ctxt, "name", dir.name :: nil);
		setenv(ctxt, "gid", dir.gid :: nil);
		setenv(ctxt, "muid", dir.muid :: nil);
		setenv(ctxt, "qid", sys->sprint("16r%ubx", dir.qid.path) :: string dir.qid.vers :: nil);
		setenv(ctxt, "atime", string dir.atime :: nil);
		setenv(ctxt, "dtype", sys->sprint("%c", dir.dtype) :: nil);
		setenv(ctxt, "dev", string dir.dev :: nil);
	}
}

start(startc: chan of (string, chan of string), name: string): chan of string
{
	c := chan of string;
	startc <-= (name, c);
	return c;
}

mtab := array[] of {
	"---",	"--x",	"-w-",	"-wx",
	"r--",	"r-x",	"rw-",	"rwx"
};

modes(mode: int): string
{
	s: string;

	if(mode & Sys->DMDIR)
		s = "d";
	else if(mode & Sys->DMAPPEND)
		s = "a";
	else if(mode & Sys->DMAUTH)
		s = "A";
	else
		s = "-";
	if(mode & Sys->DMEXCL)
		s += "l";
	else
		s += "-";
	s += mtab[(mode>>6)&7]+mtab[(mode>>3)&7]+mtab[mode&7];
	return s;
}
