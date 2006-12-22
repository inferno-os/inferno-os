implement Zeros;

include "sys.m";
	sys: Sys;
include "arg.m";
	arg: Arg;
include "string.m";
	str: String;
include "keyring.m";
include "security.m";
	random: Random;

include "draw.m";

Zeros: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	z: array of byte;
	i: int;
	sys = load Sys Sys->PATH;
	arg = load Arg Arg->PATH;
	str = load String String->PATH;

	if(sys == nil || arg == nil)
		return;

	bs := 0;
	n := 0;
	val := 0;
	rflag := 0;
	arg->init(argv);
	while ((c := arg->opt()) != 0)
		case c {
		'r' => rflag = 1;
		'v' => (val, nil) = str->toint(arg->arg(), 16);
		* => raise sys->sprint("fail:unknown option (%c)\n", c);
		}
	argv = arg->argv();
	if(len argv >= 1)
		bs = int hd argv;
	else
		bs = 1;
	if (len argv >= 2)
		n = int hd tl argv;
	else
		n = 1;
	if(bs == 0 || n == 0) {
		sys->fprint(sys->fildes(2), "usage: zeros [-r] [-v value] blocksize [number]\n");
		raise "fail:usage";
	}
	if (rflag) {
		random = load Random Random->PATH;
		if (random == nil)
			raise "fail:no security module\n";
		z = random->randombuf(random->NotQuiteRandom, bs);
	}
	else {
		z = array[bs] of byte;
		for(i=0;i<bs;i++)
			z[i] = byte val;
	}
	for(i=0;i<n;i++)
		sys->write(sys->fildes(1), z, bs);
}
