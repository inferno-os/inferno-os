implement Touchcal;

#
# calibrate a touch screen
#
# Copyright © 2001 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys:	Sys;

include "draw.m";
	draw:	Draw;
	Display, Font, Image, Point, Pointer, Rect: import draw;

include "tk.m";

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "translate.m";
	translate: Translate;
	Dict: import translate;

Touchcal: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};


Margin: con 20;

prompt:= "Please tap the centre\nof the cross\nwith the stylus";

mousepid := 0;

init(ctxt: ref Draw->Context, args: list of string)
{
	r: Rect;
	disp: ref Image;

	if(args != nil)
		args = tl args;
	debug := args != nil && hd args == "-d";
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	if(draw == nil)
		err(sys->sprint("no Draw module: %r"));
	sys->pctl(Sys->NEWPGRP|Sys->FORKFD, nil);
	translate = load Translate Translate->PATH;
	if(translate != nil){
		translate->init();
		(dict, nil) := translate->opendict(translate->mkdictname("", "touchcal"));
		if(dict != nil)
			prompt = dict.xlate(prompt);
		dict = nil;
		translate = nil;
	}

	display: ref Display;
	win: ref Window;
	ptr: chan of ref Pointer;
	if(ctxt != nil){
		display = ctxt.display;
		wmclient = load Wmclient Wmclient->PATH;
		if(wmclient == nil)
			err(sys->sprint("cannot load %s: %r", Wmclient->PATH));
		wmclient->init();
		win = wmclient->window(ctxt, "Touchcal", Wmclient->Plain);
		win.reshape(ctxt.display.image.r);
		ptr = chan of ref Pointer;
		win.onscreen("exact");
		win.startinput("ptr"::nil);
		pidc := chan of int;
		ptr = win.ctxt.ptr;
		display = ctxt.display;
		disp = win.image;
		r = disp.r;
	}else{
		# standalone, catch them ourselves
		display = draw->Display.allocate(nil);
		disp = display.image;
		r = disp.r;
		mfd := sys->open("/dev/pointer", Sys->OREAD);
		if(mfd == nil)
			err(sys->sprint("can't open /dev/pointer: %r"));
		pidc := chan of int;
		ptr = chan of ref Pointer;
		spawn rawmouse(mfd, ptr, pidc);
		mousepid = <-pidc;
	}
	white := display.white;
	black := display.black;
	red := display.color(Draw->Red);
	disp.draw(r, white, nil, r.min);
	samples := array[4] of Point;
	points := array[4] of Point;
	points[0] = (r.min.x+Margin, r.min.y+Margin);
	points[1] = (r.max.x-Margin, r.min.y+Margin);
	points[2] = (r.max.x-Margin, r.max.y-Margin);
	points[3] = (r.min.x+Margin, r.max.y-Margin);
	midpoint := Point((r.min.x+r.max.x)/2, (r.min.y+r.max.y)/2);
	refx := FX((points[1].x - points[0].x) + (points[2].x - points[3].x), 1);
	refy := FX((points[3].y - points[0].y) + (points[2].y - points[1].y), 1);
	ctl := sys->open("/dev/touchctl", Sys->ORDWR);
	if(ctl == nil)
		ctl = sys->open("/dev/null", Sys->ORDWR);
	if(ctl == nil)
		err(sys->sprint("can't open /dev/touchctl: %r"));
	#oldvalues := array[128] of byte;
	#nr := sys->read(ctl, oldvalues, len oldvalues);
	#if(nr < 0)
	#	err(sys->sprint("can't read old values from /dev/touchctl: %r"));
	#oldvalues = oldvalues[0:nr];
	sys->fprint(ctl, "X %d %d %d\nY %d %d %d\n", FX(1,1), 0, 0, 0, FX(1,1), 0);	# identity
	font := Font.open(display, sys->sprint("/fonts/lucida/unicode.%d.font", 6+(r.dx()/512)));
	if(font == nil)
		font = Font.open(display, "*default*");
	if(font != nil){
		drawtext(disp, midpoint, black, font, prompt);
		font = nil;
	}
	for(;;) {
		tm := array[] of {0 to 2 =>array[] of {0, 0, 0}};
		for(i := 0; i < 4; i++){
			cross(disp, points[i], red);
			samples[i] = getpoint(ptr);
			cross(disp, points[i], white);
		}
		# first, rotate if necessary
		rotate := 0;
		if(abs(samples[1].x-samples[2].x) > 80 && abs(samples[2].y-samples[3].y) > 80){
			rotate = 1;
			for(i = 0; i < len samples; i++)
				samples[i] = (samples[i].y, samples[i].x);
		}
		# calculate scaling and offset transformations
		actx := (samples[1].x-samples[0].x)+(samples[2].x-samples[3].x);
		acty := (samples[3].y-samples[0].y)+(samples[2].y-samples[1].y);
		if(actx == 0 || acty == 0)
			continue;		# either the user or device is not trying
		tm[0][rotate] = refx/actx;
		tm[0][2] = FX(points[0].x - XF(tm[0][rotate]*samples[0].x), 1);
		tm[1][1-rotate] = refy/acty;
		tm[1][2] = FX(points[0].y - XF(tm[1][1-rotate]*samples[0].y), 1);
		cross(disp, midpoint, red);
		m := getpoint(ptr);
		cross(disp, midpoint, white);
		p := Point(ptmap(tm[0], m.x, m.y), ptmap(tm[1], m.x, m.y));
		if(debug){
			for(k:=0; k<4; k++)
				sys->print("%d %d,%d %d,%d\n", k, points[k].x,points[k].y, samples[k].x, samples[k].y);
			if(rotate)
				sys->print("rotated\n");
			sys->print("rx=%d ax=%d ry=%d ay=%d tm[0][0]=%d\n", refx, actx, refy, acty, tm[0][0]);
			sys->print("%g %g %g\n%g %g %g\n",
				G(tm[0][0]), G(tm[0][1]), G(tm[0][2]),
				G(tm[1][0]), G(tm[1][1]), G(tm[1][2]));
			sys->print("%d %d -> %d %d (%d %d)\n", m.x, m.y, p.x, p.y, midpoint.x, midpoint.y);
		}
		if(abs(p.x-midpoint.x) > 5 || abs(p.y-midpoint.y) > 5)
			continue;
		printmat(sys->fildes(1), tm);
		if(debug || printmat(ctl, tm) >= 0){
			disp.draw(r, white, nil, r.min);
			break;
		}
		sys->fprint(sys->fildes(2), "touchcal: can't set calibration: %r\n");
	}
	if(mousepid > 0)
		kill(mousepid);
}

printmat(fd: ref Sys->FD, tm: array of array of int): int
{
	return sys->fprint(fd, "X %d %d %d\nY %d %d %d\n",
		    tm[0][0], tm[0][1], tm[0][2],
		    tm[1][0], tm[1][1], tm[1][2]);
}

FX(a, b: int): int
{
	return (a << 16)/b;
}

XF(v: int): int
{
	return v>>16;
}

G(v: int): real
{
	return real v / 65536.0;
}

ptmap(m: array of int, x, y: int): int
{
	return XF(m[0]*x + m[1]*y + m[2]);
}

rawmouse(fd: ref Sys->FD, mc: chan of ref Pointer, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	buf := array[64] of byte;
	for(;;){
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			err(sys->sprint("can't read /dev/pointer: %r"));

		if(int buf[0] != 'm' || n < 1+3*12)
			continue;

		x := int string buf[ 1:13];
		y := int string buf[12:25];
		b := int string buf[24:37];
		mc <-= ref Pointer(b, (x,y), 0);
	}
}

getpoint(mousec: chan of ref Pointer): Point
{
	p := Point(0,0);
	while((m := <-mousec).buttons == 0)
		p = m.xy;
	n := 0;
	do{
		if(abs(p.x-m.xy.x) > 10 || abs(p.y-m.xy.y) > 10){
			n = 0;
			p = m.xy;
		}else{
			p = p.mul(n).add(m.xy).div(n+1);
			n++;
		}
	}while((m = <-mousec).buttons & 7);
	return p;
}

cross(im: ref Image, p: Point, col: ref Image)
{
	im.line(p.sub((0,10)), p.add((0,10)), Draw->Endsquare, Draw->Endsquare, 0, col, col.r.min);
	im.line(p.sub((10,0)), p.add((10,0)), Draw->Endsquare, Draw->Endsquare, 0, col, col.r.min);
	im.flush(Draw->Flushnow);
}

drawtext(im: ref Image, p: Point, col: ref Image, font: ref Font, text: string)
{
	(n, lines) := sys->tokenize(text, "\n");
	p = p.sub((0, (n+1)*font.height));
	for(; lines != nil; lines = tl lines){
		s := hd lines;
		w := font.width(s);
		im.text(p.sub((w/2, 0)), col, col.r.min, font, s);
		p = p.add((0, font.height));
	}
}

abs(x: int): int
{
	if(x < 0)
		return -x;
	return x;
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "touchcal: %s\n", s);
	if(mousepid > 0)
		kill(mousepid);
	raise "fail:touch";
}
