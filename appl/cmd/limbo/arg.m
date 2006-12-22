Arg: adt
{
	argv:	list of string;
	c:	int;
	opts:	string;

	init:	fn(argv: list of string): ref Arg;
	opt:	fn(arg: self ref Arg): int;
	arg:	fn(arg: self ref Arg): string;
};

Arg.init(argv: list of string): ref Arg
{
	if(argv != nil)
		argv = tl argv;
	return ref Arg(argv, 0, nil);
}

Arg.opt(arg: self ref Arg): int
{
	if(arg.opts != ""){
		arg.c = arg.opts[0];
		arg.opts = arg.opts[1:];
		return arg.c;
	}
	if(arg.argv == nil)
		return arg.c = 0;
	arg.opts = hd arg.argv;
	if(len arg.opts < 2 || arg.opts[0] != '-')
		return arg.c = 0;
	arg.argv = tl arg.argv;
	if(arg.opts == "--")
		return arg.c = 0;
	arg.c = arg.opts[1];
	arg.opts = arg.opts[2:];
	return arg.c;
}

Arg.arg(arg: self ref Arg): string
{
	s := arg.opts;
	arg.opts = "";
	if(s != "")
		return s;
	if(arg.argv == nil)
		return "";
	s = hd arg.argv;
	arg.argv = tl arg.argv;
	return s;
}
