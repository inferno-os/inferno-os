implement Scroll;

include "common.m";

sys : Sys;
drawm : Draw;
acme : Acme;
graph : Graph;
utils : Utils;
gui : Gui;
dat : Dat;
framem : Framem;
textm : Textm;
timerm : Timerm;

BORD, BACK : import Framem;
FALSE, TRUE, XXX, Maxblock : import Dat;
error, warning : import utils;
Point, Rect, Image, Display : import drawm;
draw : import graph;
black, white, display : import gui;
mouse, cmouse : import dat;
Frame : import framem;
Timer : import Dat;
Text : import textm;
frgetmouse : import acme;
mainwin : import gui;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	drawm = mods.draw;
	acme = mods.acme;
	graph = mods.graph;
	utils = mods.utils;
	gui = mods.gui;
	dat = mods.dat;
	framem = mods.framem;
	textm = mods.textm;
	timerm = mods.timerm;
}

scrpos(r : Rect, p0 : int, p1 : int, tot : int) : Rect
{
	h : int;
	q : Rect;

	q = r;
	# q = r.inset(1);
	h = q.max.y-q.min.y;
	if(tot == 0)
		return q;
	if(tot > 1024*1024){
		tot >>= 10;
		p0 >>= 10;
		p1 >>= 10;
	}
	if(p0 > 0)
		q.min.y += h*p0/tot;
	if(p1 < tot)
		q.max.y -= h*(tot-p1)/tot;
	if(q.max.y < q.min.y+2){
		if(q.min.y+2 <= r.max.y)
			q.max.y = q.min.y+2;
		else
			q.min.y = q.max.y-2;
	}
	return q;
}

scrx : ref Image;

scrresize()
{
	scrx = nil;
	h := 1024;
	if (display != nil)
		h = display.image.r.dy();
	rr := Rect((0, 0), (32, h));
	scrx = graph->balloc(rr, mainwin.chans, Draw->White);
	if(scrx == nil)
		error("scroll balloc");
}

scrdraw(t : ref Text)
{
	r, r1, r2 : Rect;

	if(t.w==nil || t.what!=Textm->Body || t != t.w.body)
		return;
	if(scrx == nil)
		scrresize();
	r = t.scrollr;
	b := scrx;
	r1 = r;
	# r.min.x += 1;	# border between margin and bar 
	r1.min.x = 0;
	r1.max.x = r.dx();
	r2 = scrpos(r1, t.org, t.org+t.frame.nchars, t.file.buf.nc);
	if(!r2.eq(t.lastsr)){
		t.lastsr = r2;
		draw(b, r1, t.frame.cols[BORD], nil, (0, 0));
		draw(b, r2, t.frame.cols[BACK], nil, (0, 0));
		r2.min.x = r2.max.x-1;
		draw(b, r2, t.frame.cols[BORD], nil, (0, 0));
		draw(t.frame.b, r, b, nil, (0, r1.min.y));
		# bflush();
	}
}

scrsleep(dt : int)
{
	timer : ref Timer;

	timer = timerm->timerstart(dt);
	graph->bflush();
	# only run from mouse task, so safe to use cmouse 
	alt{
	<-(timer.c) =>
		timerm->timerstop(timer);
	*mouse = *<-cmouse =>
		spawn timerm->timerwaittask(timer);
	}
}

scroll(t : ref Text, but : int)
{
	p0, oldp0 : int;
	s : Rect;
	x, y, my, h, first : int;

	s = t.scrollr.inset(1);
	h = s.max.y-s.min.y;
	x = (s.min.x+s.max.x)/2;
	oldp0 = ~0;
	first = TRUE;
	do{
		graph->bflush();
		my = mouse.xy.y;
		if(my < s.min.y)
			my = s.min.y;
		if(my >= s.max.y)
			my = s.max.y;
		if(but == 2){
			y = my;
			if(y > s.max.y-2)
				y = s.max.y-2;
			if(t.file.buf.nc > 1024*1024)
				p0 = ((t.file.buf.nc>>10)*(y-s.min.y)/h)<<10;
			else
				p0 = t.file.buf.nc*(y-s.min.y)/h;
			if(oldp0 != p0)
				t.setorigin(p0, FALSE);
			oldp0 = p0;
			frgetmouse();
			continue;
		}
		if(but == 1) {
			p0 = t.backnl(t.org, (my-s.min.y)/t.frame.font.height);
			if(p0 == t.org)
				p0 = t.backnl(t.org, 1);
		}
		else {
			p0 = t.org+framem->frcharofpt(t.frame, (s.max.x, my));
			if(p0 == t.org)
				p0 = t.forwnl(t.org, 1);
		}
		if(oldp0 != p0)
			t.setorigin(p0, TRUE);	
		oldp0 = p0;
		# debounce 
		if(first){
			graph->bflush();
			sys->sleep(200);
			alt {
			*mouse = *<-cmouse =>
				;
			* =>
				;
			}
			first = FALSE;
		}
		scrsleep(80);
	}while(mouse.buttons & (1<<(but-1)));
	while(mouse.buttons)
		frgetmouse();
}
