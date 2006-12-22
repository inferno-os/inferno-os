# apply cmd to args list read from stdin
# obc
implement Xargs;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Xargs: module
{
        init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

usage()
{
	sys->fprint(stderr, "Usage: xargs command [command args] <[list of last command arg]\n");
}

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil){
		sys->fprint(stderr, "xargs: can't load Bufio: %r\n");
		exit;
	}
	if(args != nil)
		args = tl args;
	if (args == nil) {
		usage();
		return;
	}
	cmd := hd args;
	args = tl args;
	if(len cmd < 4 || cmd[len cmd -4:]!=".dis")
		cmd += ".dis";
	sh := load Command cmd;
	if (sh == nil){
		cmd = "/dis/"+cmd;
		sh = load Command cmd;
	}
	if (sh == nil){
		sys->fprint(stderr, "xargs: can't load %s: %r\n", cmd);
		exit;
	}

	stdin := sys->fildes(0);
	if(stdin == nil){
		sys->fprint(stderr, "xargs: no standard input\n");
		exit;
	}
	b := bufio->fopen(stdin, Bufio->OREAD);
	while((t := b.gets('\n')) != nil){
		(nil, rargs) := sys->tokenize(t, " \t\n");
		if (rargs == nil)
			continue;
		if (args == nil)
			rargs = cmd :: rargs;
		else
			rargs = append(cmd :: args, rargs);
		sh->init(ctxt, rargs);		# BUG: process environment?
	}
}

reverse[T](l: list of T): list of T
{
	t: list of T;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}

append(h, t: list of string) : list of string
{
	r := reverse(h);
	for(; r != nil; r = tl r)
		t = hd r :: t;
	return t;
}
