implement Os;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "ftrans.m";
	ftrans: Ftrans;

include "env.m";
	env: Env;

include "arg.m";

Os: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	if(str == nil)
		fail(sys->sprint("cannot load %s: %r", String->PATH));
	arg := load Arg Arg->PATH;
	if(arg == nil)
		fail(sys->sprint("cannot load %s: %r", Arg->PATH));

	arg->init(args);
	arg->setusage("os [-d dir] [-m mount] [-n] [-N nice] [-b] command [arg...]");

	nice := 0;
	nicearg: string;
	workdir := "";
	mntpoint := "";
	foreground := 1;
	translate := 0;
	noexe := 0;

	while((opt := arg->opt()) != 0) {
		case opt {
		'd' =>
			workdir = arg->earg();
		'E' =>
			noexe = 1;
		'm' =>
			mntpoint = arg->earg();
		'n' =>
			nice = 1;
		'N' =>
			nice = 1;
			nicearg = sys->sprint(" %q", arg->earg());
		't' =>
			translate = 1;
		'T' =>
			translate = 2;
		'b' =>
			foreground = 0;
		* =>
			arg->usage();
		}
	}
	args = arg->argv();
	if (args == nil)
		arg->usage();
	arg = nil;
	if(translate){
		if(workdir == nil)
			workdir=".";
		(workdir, args) = translatenames(args, workdir, translate>1);
	}
	if(noexe){
		s := sys->sprint("os -d %q", workdir);
		for(; args != nil; args = tl args)
			s += sys->sprint(" %q", hd args);
		sys->print("%s\n", s);
		return;
	}

	sys->pctl(Sys->FORKNS, nil);
	sys->bind("#p", "/prog", Sys->MREPL);		# don't worry if it fails
	if(mntpoint == nil){
		mntpoint = "/cmd";
		if(sys->stat(mntpoint+"/clone").t0 == -1)
		if(sys->bind("#C", "/", Sys->MBEFORE) < 0)
			fail(sys->sprint("bind #C /: %r"));
	}

	cfd := sys->open(mntpoint+"/clone", sys->ORDWR);
	if(cfd == nil)
		fail(sys->sprint("cannot open /cmd/clone: %r"));
	
	buf := array[32] of byte;
	if((n := sys->read(cfd, buf, len buf)) <= 0)
		fail(sys->sprint("cannot read /cmd/clone: %r"));

	dir := mntpoint+"/"+string buf[0:n];

	wfd := sys->open(dir+"/wait", Sys->OREAD);
	if(nice && sys->fprint(cfd, "nice%s", nicearg) < 0)
		sys->fprint(sys->fildes(2), "os: warning: can't set nice priority: %r\n");

	if(workdir != nil && sys->fprint(cfd, "dir %q", workdir) < 0)
		fail(sys->sprint("cannot set cwd %q: %r", workdir));

	if(foreground && sys->fprint(cfd, "killonclose") < 0)
		sys->fprint(sys->fildes(2), "os: warning: cannot write killonclose: %r\n");

	if(sys->fprint(cfd, "exec %s", str->quoted(args)) < 0)
		fail(sys->sprint("cannot exec: %r"));

	if(foreground){
		if((tocmd := sys->open(dir+"/data", sys->OWRITE)) == nil)
			fail(sys->sprint("canot open %s/data for writing: %r", dir));
		if((fromcmd := sys->open(dir+"/data", sys->OREAD)) == nil)
			fail(sys->sprint("cannot open %s/data for reading: %r", dir));
		if((errcmd := sys->open(dir+"/stderr", sys->OREAD)) == nil)
			sys->fprint(sys->fildes(2),  "warning: cannot open %s/stderr for reading: %r\n", dir);

		spawn copy(sync := chan of int, nil, sys->fildes(0), tocmd);
		pid := <-sync;
		tocmd = nil;

		epid := -1;
		if(errcmd != nil){
			spawn copy(sync, nil, errcmd, sys->fildes(2));
			epid = <-sync;
			sync = nil;
			errcmd = nil;
		}
	
		spawn copy(nil, done := chan of int, fromcmd, sys->fildes(1));
		fromcmd = nil;

		# cfd is still open, so if we're killgrp'ed and we're on a platform
		# (e.g. windows) where the fromcmd read is uninterruptible,
		# cfd will be closed, so the command will be killed (due to killonclose), and
		# the fromcmd read should complete, allowing that process to be killed.

		<-done;
		kill(pid);
		kill(epid);
	}

	if(wfd != nil){
		status := array[1024] of byte;
		n = sys->read(wfd, status, len status);
		if(n < 0)
			fail(sys->sprint("wait error: %r"));
		s := string status[0:n];
		if(s != nil){
			# pid user sys real status
			flds := str->unquoted(s);
			if(len flds < 5)
				fail(sys->sprint("wait error: odd status: %q", s));
			s = hd tl tl tl tl flds;
			if(0)
				sys->fprint(sys->fildes(2), "WAIT: %q\n", s);
			if(s != nil)
				raise "fail:host: "+s;
		}
	}
}

translatenames(args: list of string, dir: string, all: int): (string, list of string)
{
	ftrans = load Ftrans Ftrans->PATH;
	if(ftrans == nil)
		fail(sys->sprint("cannot load %s: %r", Ftrans->PATH));
	env = load Env Env->PATH;
	ftrans->init(nil, nil :: str->unquoted(env->getenv("ftrans")));
	arg0 := translate1(hd args);
	args = tl args;
	dir = translate1(dir);
	if(all){
		na: list of string;
		for(; args != nil; args = tl args){
			a := hd args;
			a = translate1(a);
			na = a :: na;
		}
		for(args = nil; na != nil; na = tl na)
			args = hd na :: args;
	}
	return (dir, arg0 :: args);
}

translate1(p: string): string
{
	if(p == nil)
		return nil;
	if(! (p[0] == '/' || len p > 1 && p[0:2] == "./" || (sys->stat(p).t0 != -1)))
		return p;
	if(hasdriveletter(p) == 0){
		(t, e) := ftrans->translate(p);
		if(t == nil)
			fail(sys->sprint("%s: %s", p, e));
		if(prefix(t, "#")){
			t = t[1:];
			if(!prefix(t, "U"))
				fail(p+": not in local filesystem space");
			t = t[1:];
			if(t == nil || prefix(t, "/")){
				# #U/... - rooted at $emuroot
				root := str->unquoted(env->getenv("emuroot"));
				if(len root != 1)
					fail(sys->sprint("funny $emuroot %q", env->getenv("emuroot")));
				t = hd root+t;
			}else if(prefix(t, "*")){
				# #U*/ - rooted at /
				t = t[1:];
			}else if(!hasdriveletter(t))
				fail("unknown kind of dev: #U"+t);
		}
		p = t;
	}
	if(hasdriveletter(p)){
		for(i := 0; i < len p; i++)
			if(p[i] == '/')
				p[i] = '\\';
			else if(p[i] == '␣')	# HACK!
				p[i] = ' ';
	}
	return p;
}

hasdriveletter(p: string): int
{
	return  len p > 1 && (p[0] >= 'a' && p[0] <= 'z' || p[0] >= 'A' && p[0] <= 'Z') && p[1] == ':' && (len p == 2 || (p[2] == '/' || p[2] == '\\'));
}

prefix(s, p: string): int
{
	return len s >= len p && s[0:len p] == p;
}

copy(sync, done: chan of int, f, t: ref Sys->FD)
{
	if(sync != nil)
		sync <-= sys->pctl(0, nil);
	buf := array[8192] of byte;
	for(;;) {
		r := sys->read(f, buf, len buf);
		if(r <= 0)
			break;
		w := sys->write(t, buf, r);
		if(w != r)
			break;
	}
	if(done != nil)
		done <-= 1;
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}

fail(msg: string)
{
	sys->fprint(sys->fildes(2), "os: %s\n", msg);
	raise "fail:"+msg;
}
