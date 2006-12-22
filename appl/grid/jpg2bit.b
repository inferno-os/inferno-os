implement jpg2bit;

include "sys.m";
	sys : Sys;

include "draw.m";
	draw: Draw;
	Context, Display, Point, Rect, Image, Screen, Font: import draw;

include "grid/readjpg.m";
	readjpg: Readjpg;

display : ref draw->Display;
screen : ref draw->Screen;
context : ref draw->Context;

jpg2bit : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);
};

init(ctxt : ref Draw->Context, argv : list of string)
{
	display = ctxt.display;
	screen = ctxt.screen;
	context = ctxt;

	sys = load Sys Sys->PATH;
	readjpg = load Readjpg Readjpg->PATH;
	readjpg->init(display);
	
	draw = load Draw Draw->PATH;
	argv = tl argv;
	if (argv == nil) exit;
	filename := hd argv;
	filename2 : string;
	if (tl argv == nil) {
		if (len filename > 3) filename2 = filename[:len filename - 4];
		filename2 += ".bit";
	}
	else filename2 = hd tl argv;
	img := readjpg->jpg2img(hd argv, "", chan of string, nil);
	fd := sys->create(filename2, sys->OWRITE,8r666);
	if (fd != nil)
		display.writeimage(fd,img);

}

