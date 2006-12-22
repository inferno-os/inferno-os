implement Os;

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

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
	arg->setusage("os [-d dir] [-n] command [arg...]");

	nice := 0;
	nicearg: string;
	workdir := "";
	mntpoint := "";
	while((opt := arg->opt()) != 0) {
		case opt {
		'd' =>
			workdir = arg->earg();
		'm' =>
			mntpoint = arg->earg();
		'n' =>
			nice = 1;
		'N' =>
			nice = 1;
			nicearg = sys->sprint(" %q", arg->earg());
		* =>
			arg->usage();
		}
	}
	args = arg->argv();
	if (args == nil)
		arg->usage();
	arg = nil;

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

	if(workdir != nil && sys->fprint(cfd, "dir %s", workdir) < 0)
		fail(sys->sprint("cannot set cwd %q: %r", workdir));

	if(sys->fprint(cfd, "killonclose") < 0)
		sys->fprint(sys->fildes(2), "os: warning: cannot write killonclose: %r\n");

	if(sys->fprint(cfd, "exec %s", str->quoted(args)) < 0)
		fail(sys->sprint("cannot exec: %r"));

	if((tocmd := sys->open(dir+"/data", sys->OWRITE)) == nil)
		fail(sys->sprint("canot open %s/data for writing: %r", dir));

	if((fromcmd := sys->open(dir+"/data", sys->OREAD)) == nil)
		fail(sys->sprint("cannot open %s/data for reading: %r", dir));

	spawn copy(sync := chan of int, nil, sys->fildes(0), tocmd);
	pid := <-sync;
	sync = nil;
	tocmd = nil;

	spawn copy(nil, done := chan of int, fromcmd, sys->fildes(1));

	# cfd is still open, so if we're killgrp'ed and we're on a platform
	# (e.g. windows) where the fromcmd read is uninterruptible,
	# cfd will be closed, so the command will be killed (due to killonclose), and
	# the fromcmd read should complete, allowing that process to be killed.

	<-done;
	kill(pid);

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
	sys->fprint(fd, "kill");
}

fail(msg: string)
{
	sys->fprint(sys->fildes(2), "os: %s\n", msg);
	raise "fail:"+msg;
}
