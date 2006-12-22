implement Arg;

#
# Copyright © 1997 Roger Peppe
#

include "sys.m";
include "arg.m";

name:= "";
args: list of string;
usagemsg:="";
printusage := 1;

curropt: string;

init(argv: list of string)
{
	(curropt, args, name) = (nil, nil, nil);
	if (argv == nil)
		return;
	name = hd argv;
	args = tl argv;
}

setusage(u: string)
{
	usagemsg = u;
	printusage = u != nil;
}

progname(): string
{
	return name;
}

# don't allow any more options after this function is invoked
argv(): list of string
{
	ret := args;
	args = nil;
	return ret;
}

earg(): string
{
	if (curropt != nil) {
		ret := curropt;
		curropt = nil;
		return ret;
	}

	if (args == nil)
		usage();

	ret := hd args;
	args = tl args;
	return ret;
}

# get next option argument
arg(): string
{
	if (curropt != nil) {
		ret := curropt;
		curropt = nil;
		return ret;
	}

	if (args == nil)
		return nil;

	ret := hd args;
	args = tl args;
	return ret;
}

# get next option letter
# return 0 at end of options
opt(): int
{
	if (curropt != nil) {
		opt := curropt[0];
		curropt = curropt[1:];
		return opt;
	}

	if (args == nil)
		return 0;

	nextarg := hd args;
	if (len nextarg < 2 || nextarg[0] != '-')
		return 0;

	if (nextarg == "--") {
		args = tl args;
		return 0;
	}

	opt := nextarg[1];
	if (len nextarg > 2)
		curropt = nextarg[2:];
	args = tl args;
	return opt;
}

usage()
{
	if(printusage){
		if(usagemsg != nil)
			u := "usage: "+usagemsg;
		else
			u = name + ": argument expected";
		sys := load Sys Sys->PATH;
		sys->fprint(sys->fildes(2), "%s\n", u);
	}
	raise "fail:usage";
}
