implement Rsagen;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "arg.m";

Rsagen: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("auth/rsagen [-b bits] [-t 'attr=value attr=value ...']");
	tag: string;
	nbits := 1024;
	while((o := arg->opt()) != 0)
		case o {
		'b' =>
			nbits = int arg->earg();
			if(nbits <= 0)
				arg->usage();
			if(nbits > 4096)
				error("bits must be no greater than 4096");
		't' =>
			tag = arg->earg();
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args != nil)
		arg->usage();
	arg = nil;

	sk := kr->genSK("rsa", "", nbits);
	if(sk == nil)
		error("unable to generate key");
	s := kr->sktoattr(sk);
	# need to fix the attr interface so the following isn't needed:
	s = skip(s, "alg");
	s = skip(s, "owner");
	if(tag != nil)
		tag = " "+tag;
	a := sys->aprint("key proto=rsa%s size=%d %s\n", tag, nbits, s);
	if(sys->write(sys->fildes(1), a, len a) != len a)
		error(sys->sprint("error writing key: %r"));
}

skip(s: string, attr: string): string
{
	for(i := 0; i < len s && s[i] != ' '; i++)
		{}
	if(i >= len s)
		return s;
	(nf, fld) := sys->tokenize(s[0:i], "=");
	if(nf == 2 && hd fld == attr)
		s = s[i+1:];
	return s;
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "rsagen: %s\n", s);
	raise "fail:error";
}
