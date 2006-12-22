implement Kill;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";

Kill: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;

usage()
{
	sys->fprint(stderr, "usage: kill [-g] pid|module [...]\n");
	raise "fail: usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg := load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(stderr, "kill: cannot load %s: %r\n", Arg->PATH);
		raise "fail:load";
	}

	msg := array of byte "kill";
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'g' =>
			msg = array of byte "killgrp";
		* =>
			usage();
		}

	argv := arg->argv();
	arg = nil;
	if(argv == nil)
		usage();
	n := 0;
	for(v := argv; v != nil; v = tl v) {
		s := hd v;
		if (s == nil)
			usage();
		if(s[0] >= '0' && s[0] <= '9')
			n += killpid(s, msg, 1);
		else
			n += killmod(s, msg);
	}
	if (n == 0 && argv != nil)
		raise "fail:nothing killed";
}

killpid(pid: string, msg: array of byte, sbok: int): int
{
	fd := sys->open("/prog/"+pid+"/ctl", sys->OWRITE);
	if(fd == nil) {
		err := sys->sprint("%r");
		elen := len err;
		if(sbok || err != "thread exited" && elen >= 14 && err[elen-14:] != "does not exist")
			sys->fprint(stderr, "kill: cannot open /prog/%s/ctl: %r\n", pid);
		return 0;
	}

	n := sys->write(fd, msg, len msg);
	if(n < 0) {
		err := sys->sprint("%r");
		elen := len err;
		if(sbok || err != "thread exited")
			sys->fprint(stderr, "kill: cannot kill %s: %r\n", pid);
		return 0;
	}
	return 1;
}

killmod(mod: string, msg: array of byte): int
{
	fd := sys->open("/prog", sys->OREAD);
	if(fd == nil) {
		sys->fprint(stderr, "kill: open /prog: %r\n");
		return 0;
	}

	pids: list of string;
	for(;;) {
		(n, d) := sys->dirread(fd);
		if(n <= 0) {
			if (n < 0)
				sys->fprint(stderr, "kill: read /prog: %r\n");
			break;
		}

		for(i := 0; i < n; i++)
			if (killmatch(d[i].name, mod))
				pids = d[i].name :: pids;		
	}
	if (pids == nil) {
		sys->fprint(stderr, "kill: cannot find %s\n", mod);
		return 0;
	}
	n := 0;
	for (; pids != nil; pids = tl pids)
		if (killpid(hd pids, msg, 0)) {
			sys->print("%s ", hd pids);
			n++;
		}
	if (n > 0)
		sys->print("\n");
	return n;
}

killmatch(dir, mod: string): int
{
	status := "/prog/"+dir+"/status";
	fd := sys->open(status, sys->OREAD);
	if(fd == nil)
		return 0;
	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0) {
		err := sys->sprint("%r");
		if(err != "thread exited")
			sys->fprint(stderr, "kill: cannot read %s: %s\n", status, err);
		return 0;
	}

	# module name is last field
	(nil, fields) := sys->tokenize(string buf[0:n], " ");
	for(s := ""; fields != nil; fields = tl fields)
		s = hd fields;

	# strip builtin module, e.g. Sh[$Sys]
	for(i := 0; i < len s; i++) {
		if(s[i] == '[') {
			s = s[0:i];
			break;
		}
	}

	return s == mod;
}
