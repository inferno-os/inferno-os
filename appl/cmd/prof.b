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
	init0: fn(nil: ref Draw->Context, argv: list of string): Profile->Prof;
};

ignored(s: string)
{
	sys->fprint(stderr, "prof: warning: %s ignored\n", s);
}

exits(e: string)
{
	if(profile != nil)
		profile->end();
	raise "fail:" + e;
}

pfatal(s: string)
{
	sys->fprint(stderr, "prof: %s: %s\n", s, profile->lasterror());
	exits("error");
}

badmodule(p: string)
{
	sys->fprint(stderr, "prof: cannot load %s: %r\n", p);
	exits("bad module");
}

usage(s: string)
{
	sys->fprint(stderr, "prof: %s\n", s);
	sys->fprint(stderr, "usage: prof [-bflnv] [-m modname]... [-s rate] [cmd arg ...]");
	exits("usage");
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	init0(ctxt, argv);
}

init0(ctxt: ref Draw->Context, argv: list of string): Profile->Prof
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
	begin := 0;
	rate := 0;
	ep := 0;
	wm := 0;
	exec, mods: list of string;
	while((c := arg->opt()) != 0){
		case c {
			'b' => begin = 1;
			'f' => v |= profile->FUNCTION;
			'l' => v |= profile->LINE;
			'n' => v |= profile->FULLHDR;
			'v' => v |= profile->VERBOSE;
			's' => 
				if((s := arg->arg()) == nil)
					usage("missing sample rate");
				rate = int s;
				if(rate <= 0)
					usage("bad sample rate: '" + s + "'");
			'm' =>
				if((s := arg->arg()) == nil)
					usage("missing module name");
				mods = s :: mods;
			'e' =>
				ep = 1;
			'g' =>
				wm = 1;
			* => 
				usage(sys->sprint("unknown option -%c", c));
		}
	}

	exec = arg->argv();

	if(begin && v != 0)
		ignored("output format");
	if(begin && exec != nil)
		begin = 0;
	if(begin == 0 && exec == nil){
		if(mods != nil)
			ignored("-m option");
		if(rate > 0)
			ignored("-s option");
		mods = nil;
		rate = 0;
	}

	if(rate > 0)
		profile->sample(rate);
	for( ; mods != nil; mods = tl mods)
		profile->profile(hd mods);

	if(begin){
		if(profile->start() < 0)
			pfatal("cannot start profiling");
		exit;
	}
	r := 0;
	if(exec != nil){
		if(ep)
			profile->profile(disname(hd exec));
		if(profile->start() < 0)
			pfatal("cannot start profiling");
		# r = run(ctxt, hd exec, exec);
		wfd := openwait(sys->pctl(0, nil));
		ci := chan of int;
		spawn execute(ctxt, hd exec, exec, ci);
		epid := <- ci;
		wait(wfd, epid);
	}
	if(profile->stop() < 0)
		pfatal("cannot stop profiling");
	if(exec == nil || r >= 0){
		modl := profile->stats();
		if(modl.mods == nil)
			pfatal("no profile information");
		if(wm){
			profile->end();
			return modl;
		}
		if(!(v&(profile->FUNCTION|profile->LINE)))
			v |= profile->LINE;
		if(profile->show(modl, v) < 0)
			pfatal("cannot show profile");
	}
	profile->end();
	return (nil, 0, nil);
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
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";
	c := load Command file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil){
			sys->fprint(stderr, "prof: %s: %s\n", cmd, err);
			return;
		}
	}
	c->init(ctxt, argl);
}

# run(ctxt: ref Draw->Context, cmd : string, argl : list of string): int
# {
# 	file := cmd;
# 	if(len file<4 || file[len file-4:]!=".dis")
# 		file += ".dis";
# 	c := load Command file;
# 	if(c == nil) {
# 		err := sys->sprint("%r");
# 		if(file[0]!='/' && file[0:2]!="./"){
# 			c = load Command "/dis/"+file;
# 			if(c == nil)
# 				err = sys->sprint("%r");
# 		}
# 		if(c == nil){
# 			sys->fprint(stderr, "prof: %s: %s\n", cmd, err);
# 			return -1;
# 		}
# 	}
# 	c->init(ctxt, argl);
# 	return 0;
# }

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
