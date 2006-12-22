implement Sleep;

include "sys.m";
sys: Sys;

include "draw.m";

Sleep: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if(sys == nil || argv == nil)
		return;
	argv = tl argv;
	if(argv != nil && isvalid(hd argv)){
		t := int hd argv;
		if(t > 16r7fffffff / 1000)
			t = 16r7fffffff / 1000;
		sys->sleep(t * 1000);
	} else {
		sys->fprint(sys->fildes(2), "usage: sleep time\n");
		raise "fail:usage";
	}
}

isvalid(t: string): int
{
	l := len t;
	if(l > 0 && (t[0] == '-' || t[0] == '+'))
		x := 1;
	else
		x = 0;
	ok := 0;
	while(x < l) {
		d := t[x];
		if(d < '0' || d > '9')
			return 0;
		ok = 1;
		x++;
	}
	return ok;
}
