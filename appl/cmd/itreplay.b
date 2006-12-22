implement Itreplay;

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

SUMFILE: con "summary";
MSGFILE: con "msgs";

verbosity := 3;
display_stderr := 0;
display_stdout := 0;

stderr: ref Sys->FD;


Itreplay: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};



init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
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
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'e' =>	display_stderr++;
		'o' =>	display_stdout++;
		'v' =>	verbosity = toint("v", arg->arg(), 0, 9);
		* =>		usage();
		}
	recdirl := arg->argv();
	arg = nil;
	if (recdirl == nil)
		usage();
	while (recdirl != nil) {
		dir := hd recdirl;
		recdirl = tl recdirl;
		replay(dir);
	}
}

usage()
{
	sys->fprint(stderr, "Usage: itreplay [-eo] [-v verbosity] recorddir ...\n");
	raise "fail: usage";
	exit;
}

fatal(s: string)
{
	sys->fprint(stderr, "%s\n", s);
	raise "fail: error";
	exit;
}

nomod(mod: string)
{
	sys->fprint(stderr, "Failed to load %s\n", mod);
	raise "fail: module";
	exit;
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

replay(dir: string)
{
	sl := linelist(dir+"/"+SUMFILE);
	if (sl == nil) {
		sys->fprint(stderr, "No summary file in %s\n", dir);
		return;
	}
	sline := hd sl;
	(n, toks) := sys->tokenize(sline, " ");
	if (n < 4) {
		sys->fprint(stderr, "Bad summary file in %s\n", dir);
		return;
	}
	when := int hd toks;
	toks = tl toks;
	elapsed := int hd toks;
	toks = tl toks;
	cflag := int hd toks;
	toks = tl toks;
	testspec := hd toks;
	mreport(1, when, 0, 2, sys->sprint("Processing %s: test %s ran in %dms with cflag=%d\n", dir, testspec, elapsed, cflag));
	replay_msgs(dir+"/"+MSGFILE, testspec, cflag);
	if (display_stdout) {
		mreport(2, 0, 0, 0, "Stdout from test:");
		display_file(dir+"/stdout");
	}
	if (display_stderr) {
		mreport(2, 0, 0, 0, "Stderr from test:");
		display_file(dir+"/stderr");
	}
}


replay_msgs(mfile: string, tspec: string, cflag: int)
{
	mf := bufio->open(mfile, Bufio->OREAD);
	if (mf == nil)
		return;
	(nwarns, nerrors, nfatals) := (0, 0, 0);
	stime := 0;
	etime := 0;
	while ((line := mf.gets('\n')) != nil) {
		(whens, rest) := str->splitl(line, ":");
		when := int whens;
		msg := rest[1:];
		sev := int msg[0:1];
		verb := int msg[1:2];
		body := msg[2:];
		if (sev == S_STIME) {
			stime = int body;
			mreport(2, when, 0, 3, sys->sprint("Starting test %s cflag=%d", tspec, cflag));
		}
		else if (sev == S_ETIME) {
			uetime := int body;
			elapsed := uetime-stime;
			errsum := sys->sprint("WRN:%d ERR:%d FTL:%d", nwarns, nerrors, nfatals);
			mreport(2, when+(int body-stime)/1000, 0, 3, sys->sprint("Finished test %s after %dms - %s", tspec, elapsed, errsum));
		}
		else {
			if (sev == S_WARN) {
				nwarns++;
			}
			else if (sev == S_ERROR) {
				nerrors++;
			}
			else if (sev == S_FATAL) {
				nfatals++;
			}
			mreport(3, when, sev, verb, sys->sprint("%s: %s", severs(sev), body));
		}
	}
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


severs(sevs: int): string
{
	SEVMAP :=  array[] of {"INF", "WRN", "ERR", "FTL"};
	if (sevs >= len SEVMAP)
		sstr := "UNK";
	else
		sstr = SEVMAP[sevs];
	return sstr;
}


mreport(indent: int, when: int, sev: int, verb: int, msg: string)
{
	time := "";
	if (when) {
		tm := daytime->local(when);
		time = sys->sprint("%4d%02d%02d %02d:%02d:%02d", tm.year+1900, tm.mon-1, tm.mday, tm.hour, tm.min, tm.sec);
	}
	pad := "---"[:indent];
	term := "";
	if (len msg && msg[len msg-1] != '\n')
		term = "\n";
	if (sev || verb <= verbosity)
		sys->print("%-17s %s%s%s", time, pad, msg, term);
}
