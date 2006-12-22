implement Pipe, Fsmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context: import sh;
include "alphabet/reports.m";
	Report: import Reports;
include "alphabet/fs.m";
	fs: Fs;
	Option, Value, Fschan: import fs;
	Skip, Next, Down, Quit: import fs;

Pipe: module {};

# pipe the contents of the files in a filesystem through
# a command. -1 causes one command only to be executed.
# -p and -P (exclusive to -1) cause stat modes to be set in the shell environment.
types(): string
{
	return "rxc-1-p-P";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: exec: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	fs = load Fs Fs->PATH;
	if(fs == nil)
		badmod(Fs->PATH);
	fs->init();
	sh = load Sh Sh->PATH;
	if(sh == nil)
		badmod(Sh->PATH);
	sh->initialise();
}

run(drawctxt: ref Draw->Context, nil: ref Report,
			opts: list of Option, args: list of ref Value): ref Value
{
	n := 1;
	oneflag := pflag := 0;
	for(; opts != nil; opts = tl opts){
		o := hd opts;
		case o.opt {
		'1' =>
			oneflag = 1;
		'p' =>
			pflag = 1;
		'P' =>
			pflag = 2;
		}
	}
	if(pflag && oneflag){
		sys->fprint(sys->fildes(2), "fs: exec: cannot specify -p with -1\n");
		return nil;
	}
	c := (hd args).x().i;
	cmd := (hd tl args).c().i;
	sync := chan of string;
	spawn execproc(drawctxt, sync, oneflag, pflag, c, cmd);
	sync <-= nil;
	return ref Value.Vr(sync);
}

execproc(drawctxt: ref Draw->Context, sync: chan of string, oneflag, pflag: int,
		c: Fschan, cmd: ref Sh->Cmd)
{
	sys->pctl(Sys->NEWFD, 0::1::2::nil);
	ctxt := Context.new(drawctxt);
	<-sync;
	if(<-sync != nil){
		(<-c).t1 <-= Quit;
		exit;
	}
	argv := ref Sh->Listnode(cmd, nil) :: nil;
	fd: ref Sys->FD;
	result := chan of string;
	if(oneflag){
		fd = popen(ctxt, argv, result);
		if(fd == nil){
			(<-c).t1 <-= Quit;
			sync <-= "cannot make pipe";
			exit;
		}
	}

	names: list of string;
	name: string;
	indent := 0;
	for(;;){
		(d, reply) := <-c;
		if(d.dir == nil){
			reply <-= Next;
			if(--indent == 0){
				break;
			}
			(name, names) = (hd names, tl names);
			continue;
		}
		if((d.dir.mode & Sys->DMDIR) != 0){
			reply <-= Down;
			names = name :: names;
			if(indent > 0 && name != nil && name[len name - 1] != '/')
				name[len name] = '/';
			name += d.dir.name;
			indent++;
			continue;
		}
		if(!oneflag){
			p := name;
			if(p != nil && p[len p - 1] != '/')
				p[len p] = '/';
			setenv(ctxt, "file", p + d.dir.name :: nil);
			if(pflag)
				setstatenv(ctxt, d.dir, pflag);
			fd = popen(ctxt, argv, result);
		}
		if(fd == nil){
			reply <-= Next;
			continue;
		}
		reply <-= Down;
		for(;;){
			data: array of byte;
			((nil, data), reply) = <-c;
			reply <-= Next;
			if(data == nil)
				break;
			n := -1;
			{n = sys->write(fd, data, len data);}exception {"write on closed pipe" => ;}
			if(n != len data){
				if(oneflag){
					(<-c).t1 <-= Quit;
					sync <-= "truncated write";
					exit;
				}
				(<-c).t1 <-= Skip;
				break;
			}
		}
		if(!oneflag){
			fd = nil;
			<-result;
		}
	}
	fd = nil;
	if(oneflag)
		sync <-= <-result;
	else
		sync <-= nil;
}

popen(ctxt: ref Context, argv: list of ref Sh->Listnode, result: chan of string): ref Sys->FD
{
	sync := chan of int;
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	spawn runcmd(ctxt, argv, fds[0], sync, result);
	<-sync;
	return fds[1];
}

runcmd(ctxt: ref Context, argv: list of ref Sh->Listnode, stdin: ref Sys->FD, sync: chan of int, result: chan of string)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sys->pctl(Sys->NEWFD, 0::1::2::nil);
	ctxt = ctxt.copy(0);
	sync <-= 0;
	r := ctxt.run(argv, 0);
	ctxt = nil;
	sys->pctl(Sys->NEWFD, nil);
	result <-=r;
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
