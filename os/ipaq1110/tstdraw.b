implement Test;

include "sys.m";

include "draw.m";

Test: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys := load Sys Sys->PATH;
	draw := load Draw Draw->PATH;
	Display, Font, Rect, Point, Image, Screen: import draw;

	#
	# Set up connection to display, or use the existing one
	# if provided.
	#
	display: ref Display;
	disp: ref Image;
	if (ctxt == nil) {
		display = draw->Display.allocate(nil);
		disp = display.image;
	} else {
		display = ctxt.display;
		disp = ctxt.screen.newwindow(display.image.r, Draw->White);
	}

	#
	# Initialize colours.
	#
	red := display.color(Draw->Red);
	blue := display.color(Draw->Blue);
	white := display.color(Draw->White);
	yellow := display.color(Draw->Yellow);
	ones := display.ones;

	#
	# Paint the screen red.
	#
	disp.draw(disp.r, red, ones, disp.r.min);
	sys->sleep(5000);

	#
	# Texture a region with rectangular tiles.
	#
	texture := display.newimage(((0,0),(2,3)), disp.ldepth, 1, 0);
	texture.clipr = ((-10000,-10000),(10000,10000));
	# put something in the texture
	texture.draw(((0,0),(1,3)), blue, ones, (0,0));
	texture.draw(((0,0),(2, 1)), blue, ones, (0,0));
	# use texture as both source and mask to let
	# destination colour show through
	disp.draw(((100,100),(200,200)), texture, texture, (0,0));
	sys->sleep(5000);

	#
	# White-out a quarter of the pixels in a region,
	# to make the region appear shaded.
	#
	stipple := display.newimage(((0,0),(2,2)), disp.ldepth, 1, 0);
	stipple.draw(((0,0),(1,1)), ones, ones, (0,0));
	disp.draw(((100,100),(300,200)), white, stipple, (0,0));
	sys->sleep(5000);

	#
	# Draw textured characters.
	#
	font := Font.open(display, "*default*");
	disp.text((100,210), texture, (0,0), font, "Hello world");
	sys->sleep(5000);

	#
	# Draw picture in elliptical frame.
	#
	delight := display.open("/icons/delight.bit");
	piccenter := delight.r.min.add(delight.r.max).div(2);
	disp.fillellipse((200,100), 150, 50, delight, piccenter);
	disp.ellipse((200,100), 150, 50, 3, yellow, (0,0));
	sys->sleep(5000);

	#
	# Draw a parabolic brush stroke using an elliptical brush
	# to reveal more of the picture, consistent with what's
	# already visible.
	#
	dx : con 15;
	dy : con 3;
	brush := display.newimage(((0,0),(2*dx+1,2*dy+1)), disp.ldepth,
                               0, 0);
	brush.fillellipse((dx,dy), dx, dy, ones, (0,0));
	for(x:=delight.r.min.x; x<delight.r.max.x; x++){
		y := (x-piccenter.x)*(x-piccenter.x)/80;
		y += 2*dy+1;	# so whole brush is visible at top
		xx := x+(200-piccenter.x)-dx;
		yy := y+(100-piccenter.y)-dy;
		disp.gendraw(((xx,yy),(xx+2*dx+1,yy+2*dy+1)),
                       delight, (x-dx, y-dy), brush, (0,0));
	}
	for (i := 0; i < 500; i++) {
		disp.draw(disp.r, disp, ones, (0, 10));
		sys->sleep(5);
	}
} 
