implement Src;

include "sys.m";
	sys: Sys;
include "draw.m";
include "dis.m";
	dis: Dis;

Src: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	dis = load Dis Dis->PATH;

	if(dis != nil){
		dis->init();
		for(argv = tl argv; argv != nil; argv = tl argv){
			src := dis->src(hd argv);
			if(src == nil)
				src = "?";
			sys->print("%s:	%s\n", hd argv, src);
		}
	}
}
