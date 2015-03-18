implement Prof;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "profile.m";
	profile: Profile;
include "sh.m";

stderr: ref Sys->FD;

Prof: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
	init0: fn(nil: ref Draw->Context, argv: list of string): Profile->Coverage;
};

exits(e: string)
{
	if(profile != nil)
		profile->end();
	raise "fail:" + e;
}

pfatal(s: string)
{
	sys->fprint(stderr, "cprof: %s: %s\n", s, profile->lasterror());
	exits("error");
}

badmodule(p: string)
{
	sys->fprint(stderr, "cprof: cannot load %s: %r\n", p);
	exits("bad module");
}

usage(s: string)
{
	sys->fprint(stderr, "cprof: %s\n", s);
	sys->fprint(stderr, "usage: cprof [-fner] [-m modname]... cmd [arg ... ]\n");
	exits("usage");
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	init0(ctxt, argv);
}

init0(ctxt: ref Draw->Context, argv: list of string): Profile->Coverage
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	arg = load Arg Arg->PATH;
	if(arg == nil)
		badmodule(Arg->PATH);
	arg->init(argv);
	profile = load Profile Profile->PATH;
	if(profile == nil)
		badmodule(Profile->PATH);
	if(profile->init() < 0)
		pfatal("cannot initialize profile device");

	v := 0;
	ep := 0;
	rec := 0;
	wm := 0;
	exec, mods: list of string;
	while((c := arg->opt()) != 0){
		case c {
			'n' => v |= profile->FULLHDR;
			'f' => v |= profile->FREQUENCY;
			'm' =>
				if((s := arg->arg()) == nil)
					usage("missing module/file");
				mods = s :: mods;
			'e' =>
				ep = 1;
			'r' =>
				rec = 1;
			'g' =>
				wm = 1;
			* => 
				usage(sys->sprint("unknown option -%c", c));
		}
	}
	exec = arg->argv();
	# if(exec == nil)
	#	usage("nothing to execute");
	for( ; mods != nil; mods = tl mods)
		profile->profile(hd mods);
	if(ep && exec != nil)
		profile->profile(disname(hd exec));
	if(exec != nil){
		wfd := openwait(sys->pctl(0, nil));
		ci := chan of int;
		spawn execute(ctxt, hd exec, exec, ci);
		epid := <- ci;
		if(profile->cpstart(epid) < 0){
			ci <-= 0;
			pfatal("cannot start profiling");
		}
		ci <-= 1;
		wait(wfd, epid);
		if(profile->stop() < 0)
			pfatal("cannot stop profiling");
	}
	if(exec == nil)
		modl := profile->cpfstats(v);
	else
		modl = profile->cpstats(rec, v);
	if(modl.mods == nil)
		pfatal("no profile information");
	if(wm){
		cvr := profile->coverage(modl, v);
		profile->end();
		return cvr;
	}
	if(!rec && profile->cpshow(modl, v) < 0)
		pfatal("cannot show profile");
	profile->end();
	return nil;
}

disname(cmd: string): string
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";
	if(exists(file))
		return file;
	if(file[0]!='/' && file[0:2]!="./")
		file = "/dis/"+file;
	# if(exists(file))
	#	return file;
	return file;
}

execute(ctxt: ref Draw->Context, cmd : string, argl : list of string, ci: chan of int)
{
	ci <-= sys->pctl(Sys->FORKNS|Sys->NEWFD|Sys->NEWPGRP, 0 :: 1 :: 2 :: stderr.fd :: nil);
	file := cmd;
	err := "";
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";
	c := load Command file;
	if(c == nil) {
		err = sys->sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
	}
	if(<- ci){
		if(c == nil)
			sys->fprint(stderr, "cprof: %s: %s\n", cmd, err);
		else
			c->init(ctxt, argl);
	}
}

openwait(pid : int) : ref Sys->FD
{
	w := sys->sprint("#p/%d/wait", pid);
	fd := sys->open(w, Sys->OREAD);
	if (fd == nil)
		pfatal("fd == nil in wait");
	return fd;
}

wait(wfd : ref Sys->FD, wpid : int)
{
	n : int;

	buf := array[Sys->WAITLEN] of byte;
	status := "";
	for(;;) {
		if ((n = sys->read(wfd, buf, len buf)) < 0)
			pfatal("bad read in wait");
		status = string buf[0:n];
		if (int status == wpid)
			break;
	}
}

exists(f: string): int
{
	return sys->open(f, Sys->OREAD) != nil;
}
