implement Echo;

include "sys.m";
	sys: Sys;
include "draw.m";

Echo: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	if(args != nil)
		args = tl args;
	addnl := 1;
	if(args != nil && (hd args == "-n" || hd args == "--")) {
		if(hd args == "-n")
			addnl = 0;
		args = tl args;
	}
	s := "";
	if(args != nil) {
		s = hd args;
		while((args = tl args) != nil)
			s += " " + hd args;
	}
	if(addnl)
		s[len s] = '\n';
	a := array of byte s;
	if(sys->write(sys->fildes(1), a, len a) < 0){
		sys->fprint(sys->fildes(2), "echo: write error: %r\n");
		raise "fail:write error";
	}
}
