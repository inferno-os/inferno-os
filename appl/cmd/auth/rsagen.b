implement Rsagen;

include "sys.m";
	sys: Sys;

include "draw.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;

include "arg.m";

Rsagen: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;

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

	sk := crypt->rsagen(nbits, 6, 0);
	if(sk == nil)
		error("unable to generate key");
	if(tag != nil)
		tag = " "+tag;
	s := add("ek", sk.pk.ek);
	s += add("n", sk.pk.n);
	s += add("!dk", sk.dk);
	s += add("!p", sk.p);
	s += add("!q", sk.q);
	s += add("!kp", sk.kp);
	s += add("!kq", sk.kq);
	s += add("!c2", sk.c2);
	a := sys->aprint("key proto=rsa%s size=%d%s\n", tag, sk.pk.n.bits(), s);
	if(sys->write(sys->fildes(1), a, len a) != len a)
		error(sys->sprint("error writing key: %r"));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "rsagen: %s\n", s);
	raise "fail:error";
}

add(name: string, b: ref IPint): string
{
	return " "+name+"="+b.iptostr(16);
}
