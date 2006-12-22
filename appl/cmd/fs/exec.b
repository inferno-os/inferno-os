implement Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context: import sh;
include "fslib.m";
	fslib: Fslib;
	Option, Value, Entrychan, Report: import fslib;

# usage: exec [-n nfiles] [-t endcmd] [-pP] command entries
types(): string
{
	return "vct-ns-tc-p-P";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: exec: cannot load %s: %r\n", p);
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

run(drawctxt: ref Draw->Context, report: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	n := 1;
	pflag := 0;
	tcmd: ref Sh->Cmd;
	for(; opts != nil; opts = tl opts){
		o := hd opts;
		case o.opt {
		'n' =>
			if((n = int (hd o.args).s().i) <= 0){
				sys->fprint(sys->fildes(2), "fs: exec: invalid argument to -n\n");
				return nil;
			}
		't' =>
			tcmd = (hd o.args).c().i;
		'p' =>
			pflag = 1;
		'P' =>
			pflag = 2;
		}
	}
	if(pflag && n > 1){
		sys->fprint(sys->fildes(2), "fs: exec: cannot specify -p with -n %d\n", n);
		return nil;
	}
	cmd := (hd args).c().i;
	c := (hd tl args).t().i;
	sync := chan of int;
	spawn execproc(drawctxt, sync, n, pflag, c, cmd, tcmd, report.start("exec"));
	sync <-= 1;
	return ref Value.V(sync);
}

execproc(drawctxt: ref Draw->Context, sync: chan of int, n, pflag: int,
		c: Entrychan, cmd, tcmd: ref Sh->Cmd, errorc: chan of string)
{
	sys->pctl(Sys->NEWFD, 0::1::2::nil);
	ctxt := Context.new(drawctxt);
	<-sync;
	if(<-sync == 0){
		c.sync <-= 0;
		errorc <-= nil;
		exit;
	}
	c.sync <-= 1;
	argv := ref Sh->Listnode(cmd, nil) :: nil;

	fl: list of ref Sh->Listnode;
	nf := 0;
	while(((d, p, nil) := <-c.c).t0 != nil){
		fl = ref Sh->Listnode(nil, p) :: fl;
		if(++nf >= n){
			ctxt.set("file", rev(fl));
			if(pflag)
				setstatenv(ctxt, d, pflag);
			fl = nil;
			nf = 0;
			{ctxt.run(argv, 0);} exception {"fail:*" =>;}
		}
	}
	if(nf > 0){
		ctxt.set("file", rev(fl));
		{ctxt.run(argv, 0);} exception {"fail:*" =>;}
	}
	if(tcmd != nil){
		ctxt.set("file", nil);
		{ctxt.run(ref Sh->Listnode(tcmd, nil) :: nil, 0);} exception {"fail:*" =>;}
	}
	errorc <-= nil;
}

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

rev[T](x: list of T): list of T
{
	l: list of T;
	for(; x != nil; x = tl x)
		l = hd x :: l;
	return l;
}
