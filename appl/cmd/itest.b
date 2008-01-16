implement Itest;

include "sys.m";
	sys: Sys;
include "string.m";
	str: String;
include "draw.m";
include "daytime.m";
	daytime: Daytime;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "readdir.m";
	readdir: Readdir;
include "arg.m";
include "itslib.m";
	S_INFO, S_WARN, S_ERROR, S_FATAL, S_STIME, S_ETIME: import Itslib;
include "env.m";
	env: Env;
include "sh.m";

SUMFILE: con "summary";
MSGFILE: con "msgs";
README: con "README";

configfile := "";
cflag := -1;
verbosity := 3;
repcount := 1;
recroot := "";
display_stderr := 0;
display_stdout := 0;
now := 0;

stdout: ref Sys->FD;
stderr: ref Sys->FD;
context: ref Draw->Context;

Test: adt {
	spec: string;
	fullspec: string;
	cmd: Command;
	recdir: string;
	stdout: string;
	stderr: string;
	nruns: int;
	nwarns: int;
	nerrors: int;
	nfatals: int;
	failed: int;
};


Itest: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};



init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);
	context = ctxt;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		nomod(Daytime->PATH);
	str = load String String->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		nomod(Bufio->PATH);
	if(str == nil)
		nomod(String->PATH);
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		nomod(Readdir->PATH);
	env = load Env Env->PATH;
	if(env == nil)
		nomod(Env->PATH);
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'c' =>	cflag = toint("c", arg->arg(), 0, 9);
		'e' =>	display_stderr++;
		'o' =>	display_stdout++;
		'r' =>		repcount = toint("r", arg->arg(), 0, -1);
		'v' =>	verbosity = toint("v", arg->arg(), 0, 9);
		'C' =>	configfile = arg->arg();
		'R' =>	recroot = arg->arg();
		* =>		usage();
		}
	args = arg->argv();
	arg = nil;
	testlist : array of ref Test;
	if (args != nil)
		testlist = arg_tests(args);
	else if (configfile != "")
		testlist = config_tests(configfile);
	if (testlist == nil)
		fatal("No tests to run");
	sys->pctl(Sys->FORKENV, nil);
	if (env->setenv(Itslib->ENV_VERBOSITY, string verbosity))
		fatal("Failed to set environment variable " + Itslib->ENV_VERBOSITY);
	if (repcount) 
		reps := string repcount;
	else
		reps = "infinite";
	if (len testlist == 1) ts := "";
	else ts = "s";
	if (repcount == 1) rs := "";
	else rs = "s";
	mreport(0, S_INFO, 2, sys->sprint("Starting tests - %s run%s of %d test%s", reps, rs, len testlist, ts));
	run := big 1;

	if (recroot != nil) 
		recn := highest(recroot) + 1;
	while (repcount == 0 || run <= big repcount) {
		mreport(1, S_INFO, 3, sys->sprint("Starting run %bd", run));
		for (i:=0; i<len testlist; i++) {
			t := testlist[i];
			if (recroot != nil) {
				t.recdir = sys->sprint("%s/%d", recroot, recn++);
				mreport(2, S_INFO, 3, sys->sprint("Recording in %s", t.recdir));
				rfd := sys->create(t.recdir, Sys->OREAD, Sys->DMDIR | 8r770);
				if (rfd == nil)
					fatal(sys->sprint("Failed to create directory %s: %r\n", t.recdir));
				rfd = nil;
			}
			runtest(t);
		}
		mreport(1, S_INFO, 3, sys->sprint("Finished run %bd", run));
		run++;
	}
	mreport(0, S_INFO, 2, "Finished tests");
}

usage()
{
	sys->fprint(stderr, "Usage itest [-eo] [-c cflag] [-r count] [-v vlevel] [-C cfile] [-R recroot] [testdir ...]\n");
	raise "fail: usage";
}

fatal(s: string)
{
	sys->fprint(stderr, "%s\n", s);
	raise "fail: error";
}

nomod(mod: string)
{
	sys->fprint(stderr, "Failed to load %s\n", mod);
	raise "fail: module";
}

toint(opt, s: string, min, max: int): int
{
	if (len s == 0 || str->take(s, "[0-9]+-") != s)
		fatal(sys->sprint("no value specified for option %s", opt));
	v := int s;
	if (v < min)
		fatal(sys->sprint("option %s value is less than minimum of %d: %d", opt, v, min));
	if (max != -1 && v > max)
		fatal(sys->sprint("option %s value is greater than maximum of %d: %d", opt, v, max));
	return v;
}

arg_tests(args: list of string): array of ref Test
{
	al := len args;
	ta := array[al] of ref Test;
	for (i:=0; i<al; i++) {
		tspec := hd args;
		args = tl args;
		ta[i] = ref Test(tspec, "", nil, "", "", "", 0, 0, 0, 0, 0);
		tcheck(ta[i]);
	}
	return ta;
}

config_tests(cf: string): array of ref Test
{
	cl := linelist(cf);
	if (cl == nil)
		fatal("No tests in config file");
	al := len cl;
	ta := array[al] of ref Test;
	for (i:=0; i<al; i++) {
		tspec := hd cl;
		cl = tl cl;
		ta[i] = ref Test(tspec, "", nil, "", "", "", 0, 0, 0, 0, 0);
		tcheck(ta[i]);
	}
	return ta;

}

highest(path: string): int
{
	(da, nd) := readdir->init(path, Readdir->NAME);
	high := 0;
	for (i:=0; i<nd; i++) {
		n := int da[i].name;
		if (n > high)
			high = n;	
	}
	return high;
}

tcheck(t: ref Test): int
{
	td := t.spec;
	if (!checkdir(td)) {
		fatal(sys->sprint("Failed to find test %s\n", td));
		return 0;
	}
	tf1 := t.spec + "/t.sh";
	tf2 := t.spec + "/t.dis";
	if (checkexec(tf1)) {
		t.fullspec = tf1;
		return 1;
	}
	if (checkexec(tf2)) {
		t.fullspec = tf2;
		return 1;
	}
	fatal(sys->sprint("Could not find executable files %s or %s\n", tf1, tf2));
	return 0;
}

checkdir(d: string): int
{
	(ok, dir) := sys->stat(d);
	if (ok != 0 || ! dir.qid.qtype & Sys->QTDIR)
		return 0;
	return 1;
}

checkexec(d: string): int
{
	(ok, dir) := sys->stat(d);
	if (ok != 0 || ! dir.mode & 8r100)
		return 0;
	return 1;
}


set_cflag(f: int)
{
	wfile("/dev/jit", string f, 0);

}

runtest(t: ref Test)
{
	if (t.failed)
		return;

	if (cflag != -1) {
		mreport(0, S_INFO, 7, sys->sprint("Setting cflag to %d", cflag));
		set_cflag(cflag);
	}
	readme := t.spec + "/" + README;
	mreport(2, S_INFO, 3, sys->sprint("Starting test %s cflag=%s", t.spec, rfile("/dev/jit")));
	if (verbosity > 8)
		display_file(readme);
	sync := chan of int;
	spawn monitor(t, sync);
	<-sync;
}

monitor(t: ref Test, sync: chan of int)
{
	pid := sys->pctl(Sys->FORKFD|Sys->FORKNS|Sys->FORKENV|Sys->NEWPGRP, nil);
	pa := array[2] of ref Sys->FD;
	if (sys->pipe(pa))
		fatal("Failed to set up pipe");
	if (env->setenv(Itslib->ENV_MFD, string pa[0].fd))
		fatal("Failed to set environment variable " + Itslib->ENV_MFD);
	mlfd: ref Sys->FD;
	if (t.recdir != nil) {
		mfile := t.recdir+"/"+MSGFILE;
		mlfd = sys->create(mfile, Sys->OWRITE, 8r660);
		if (mlfd == nil)
			fatal(sys->sprint("Failed to create %s: %r'\n", mfile));
		t.stdout = t.recdir+"/stdout";
		t.stderr = t.recdir+"/stderr";
	} else {
		t.stdout = "/tmp/itest.stdout";
		t.stderr = "/tmp/itest.stderr";
	}
	cf := int rfile("/dev/jit");
	stime := sys->millisec();
	swhen := daytime->now();
	etime := -1;
	rsync := chan of int;
	spawn runit(t.fullspec, t.stdout, t.stderr, t.spec, pa[0], rsync);
	<-rsync;
	pa[0] = nil;
	(nwarns, nerrors, nfatals) := (0, 0, 0);
	while (1) {
		mbuf := array[Sys->ATOMICIO] of byte;
		n := sys->read(pa[1], mbuf, len mbuf);
		if (n <= 0) break;
		msg := string mbuf[:n];
		sev := int msg[0:1];
		verb := int msg[1:2];
		body := msg[2:];
		if (sev == S_STIME)
			stime = int body;
		else if (sev == S_ETIME)
			etime = int body;
		else {
			if (sev == S_WARN) {
				nwarns++;
				t.nwarns++;
			}
			else if (sev == S_ERROR) {
				nerrors++;
				t.nerrors++;
			}
			else if (sev == S_FATAL) {
				nfatals++;
				t.nfatals++;
			}
			mreport(3, sev, verb, sys->sprint("%s: %s", severs(sev), body));
		}
		if (mlfd != nil)
			sys->fprint(mlfd, "%d:%s", now, msg);
	}
	if (etime < 0) {
		etime = sys->millisec();
		if (mlfd != nil)
			sys->fprint(mlfd, "%d:%s", now, sys->sprint("%d0%d\n", S_ETIME, etime));
	}
	elapsed := etime-stime;
	errsum := sys->sprint("WRN:%d ERR:%d FTL:%d", nwarns, nerrors, nfatals);
	mreport(2, S_INFO, 3, sys->sprint("Finished test %s after %dms - %s", t.spec, elapsed, errsum));
	if (t.recdir != "") {
		wfile(t.recdir+"/"+SUMFILE, sys->sprint("%d %d %d %s\n", swhen, elapsed, cf, t.fullspec), 1);
	}
	if (display_stdout) {
		mreport(2, 0, 0, "Stdout from test:");
		display_file(t.stdout);
	}
	if (display_stderr) {
		mreport(2, 0, 0, "Stderr from test:");
		display_file(t.stderr);
	}
	sync <-= pid;
}

runit(fullspec, sofile, sefile, tpath: string, mfd: ref Sys->FD, sync: chan of int)
{
	pid := sys->pctl(Sys->NEWFD|Sys->FORKNS, mfd.fd::nil);
	o, e: ref Sys->FD;
	o = sys->create(sofile, Sys->OWRITE, 8r660);
	if (o == nil)
		treport(mfd, S_ERROR, 0, "Failed to open stdout: %r\n");
	else
		sys->dup(o.fd, 1);
	o = nil;
	e = sys->create(sefile, Sys->OWRITE, 8r660);
	if (e == nil)
		treport(mfd, S_ERROR, 0, "Failed to open stderr: %r\n");
	else
		sys->dup(e.fd, 2);
	e = nil;
	sync <-= pid;
	args := list of {fullspec};
	if (fullspec[len fullspec-1] == 's')
		cmd := load Command fullspec;
	else {
		cmd = load Command "/dis/sh.dis";
		args = fullspec :: args;
	}
	if (cmd == nil) {
		treport(mfd, S_FATAL, 0, sys->sprint("Failed to load Command from %s", "/dis/sh.dis"));
		return;
	}
	if (sys->chdir(tpath))
		treport(mfd, S_FATAL, 0, "Failed to cd to " + tpath);
	{
		cmd->init(context, args);
	} exception ex {
		"*" =>
		treport(mfd, S_FATAL, 0, sys->sprint("Exception %s in test %s", ex, fullspec));
	}			
}

severs(sevs: int): string
{
	SEVMAP :=  array[] of {"INF", "WRN", "ERR", "FTL"};
	if (sevs >= len SEVMAP)
		sstr := "UNK";
	else
		sstr = SEVMAP[sevs];
	return sstr;
}


rfile(file: string): string
{
	fd := sys->open(file, Sys->OREAD);
	if (fd == nil) return nil;
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(fd, buf, len buf);
	return string buf[:n];
}


wfile(file: string, text: string, create: int): int
{
	if (create)
		fd := sys->create(file, Sys->OWRITE, 8r660);
	else 
		fd = sys->open(file, Sys->OWRITE);
	if (fd == nil) {
		sys->fprint(stderr, "Failed to open %s: %r\n", file);
		return 0;
	}
	a := array of byte text;
	al := len a;
	if (sys->write(fd, a, al) != al) {
		sys->fprint(stderr, "Failed to write to %s: %r\n", file);
		return 0;
	}
	fd = nil;
	return 1;
}

linelist(file: string): list of string
{
	bf := bufio->open(file, Bufio->OREAD);
	if (bf == nil)
		return nil;
	cl : list of string;
	while ((line := bf.gets('\n')) != nil) {
		if (line[len line -1] == '\n')
			line = line[:len line - 1];
		cl = line :: cl;
	}
	bf = nil;
	return cl;
}

display_file(file: string)
{
	bf := bufio->open(file, Bufio->OREAD);
	if (bf == nil)
		return;
	while ((line := bf.gets('\n')) != nil) {
		sys->print("                    %s", line);
	}
}

mreport(indent: int, sev: int, verb: int, msg: string)
{
	now = daytime->now();
	tm := daytime->local(now);
	time := sys->sprint("%4d%02d%02d %02d:%02d:%02d", tm.year+1900, tm.mon-1, tm.mday, tm.hour, tm.min, tm.sec);
	pad := "---"[:indent];
	term := "";
	if (len msg && msg[len msg-1] != '\n')
		term = "\n";
	if (sev || verb <= verbosity)
		sys->print("%s %s%s%s", time, pad, msg, term);
}


treport(mfd: ref Sys->FD, sev: int, verb: int, msg: string)
{
	sys->fprint(mfd, "%d%d%s\n", sev, verb, msg);
}
