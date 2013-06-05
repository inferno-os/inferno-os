implement Dsagen;

include "sys.m";
	sys: Sys;

include "draw.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;

include "arg.m";

Dsagen: module
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
	arg->setusage("auth/dsagen [-t 'attr=value attr=value ...']");
	tag: string;
	while((o := arg->opt()) != 0)
		case o {
		't' =>
			tag = arg->earg();
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args != nil)
		arg->usage();
	arg = nil;

	sk := crypt->dsagen(nil);
	if(tag != nil)
		tag = " "+tag;
	s := add("p", sk.pk.p);
	s += add("q", sk.pk.q);
	s += add("alpha", sk.pk.alpha);
	s += add("key", sk.pk.key);
	s += add("!secret", sk.secret);
	a := sys->aprint("key proto=dsa%s%s\n", tag, s);
	if(sys->write(sys->fildes(1), a, len a) != len a)
		error(sys->sprint("error writing key: %r"));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "dsagen: %s\n", s);
	raise "fail:error";
}

add(name: string, b: ref IPint): string
{
	return " "+name+"="+b.iptostr(16);
}
