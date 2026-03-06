implement Wmclient;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Image, Screen, Rect, Point, Pointer, Wmcontext, Context: import draw;
include "wmlib.m";
	wmlib: Wmlib;
	qword, splitqword, s2r: import wmlib;
include "wmclient.m";
include "lucitheme.m";

Focusnone, Focusimage, Focustitle: con iota;

Bdup: con int 16rffffffff;
Bddown: con int 16radadadff;

# Colours loaded from theme; defaults kept as fallback
bdfocused:   int = int 16r448888ff;
bdunfocused: int = int 16r1a1a1aff;
screenbg:    int = int 16r000000ff;	# screen fill shown between windows

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if(wmlib == nil){
		sys->fprint(sys->fildes(2), "wmclient: cannot load %s: %r\n", Wmlib->PATH);
		raise "fail:bad module";
	}
	wmlib->init();

	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bdfocused   = th.accent;
		bdunfocused = th.border;
		screenbg    = th.bg;
	}
}

makedrawcontext(): ref Draw->Context
{
	return wmlib->makedrawcontext();
}
		
blankwin: Window;
window(ctxt: ref Draw->Context, nil: string, buts: int): ref Window
{
	w := ref blankwin;
	w.ctxt = wmlib->connect(ctxt);
	w.display = ctxt.display;
	w.ctl = chan[2] of string;
	readscreenrect(w);

	if(buts & Plain)
		return w;

	if(ctxt.wm == nil)
		buts &= ~(Resize|Hide);

	w.bd = 4;

	w.wmctl("fixedorigin");
	return w;
}

Window.pointer(w: self ref Window, p: Draw->Pointer): int
{
	if(w.screen == nil)
		return 0;

	# Scroll wheel events (buttons 8/16) should pass through without focus changes
	if(p.buttons & (8|16))
		return 0;

	if(p.buttons && (w.ptrfocus == Focusnone || w.buttons == 0)){
		if(inborder(w, p.xy))
			w.ptrfocus = Focustitle;
		else
			w.ptrfocus = Focusimage;
	}
	w.buttons = p.buttons;
	if(w.ptrfocus == Focustitle){
		if(p.buttons & (2|4))
			w.ctl <-= sys->sprint("!size . -1 %d %d", 0, 0);
		else if(p.buttons & 1){
			w.ctl <-= sys->sprint("!move . -1 %d %d", p.xy.x, p.xy.y);
		}
		return 1;
	}
	return 0;
}

# titlebar requested size might have changed:
# find out what size it's requesting.
sizetb(nil: ref Window)
{
	return;
}

# reshape the image; the space needed for the
# titlebar is added to r.
Window.reshape(w: self ref Window, r: Rect)
{
	w.r = w.screenr(r);
	if(w.screen == nil)
		return;
	w.wmctl(sys->sprint("!reshape . -1 %s", r2s(w.r)));
}

putimage(w: ref Window, i: ref Image)
{
	if(w.screen != nil && i == w.screen.image)
		return;
#	display := w.ctxt.ctxt.display;
	w.screen = Screen.allocate(i, w.display.color(screenbg), 0);
	ir := i.r.inset(w.bd);
	if(ir.dx() < 0)
		ir.max.x = ir.min.x;
	if(ir.dy() < 0)
		ir.max.y = ir.min.y;
	if(ir.dy() < 0)
		ir.max.y = ir.min.y;
	w.image = w.screen.newwindow(ir, Draw->Refnone, Draw->Nofill);
	drawborder(w);
	w.r = i.r;
}

# return a rectangle suitable to hold image r when the
# titlebar and border are included.
Window.screenr(w: self ref Window, r: Rect): Rect
{
	return r.inset(-w.bd);
}

# return the available space inside r when space for
# border and titlebar is taken away.
Window.imager(w: self ref Window, r: Rect): Rect
{
	r = r.inset(w.bd);
	if(r.dx() < 0)
		r.max.x = r.min.x;
	if(r.dy() < 0)
		r.max.y = r.min.y;
	return r;
}

# draw an imitation tk border.
drawborder(w: ref Window)
{
	if(w.screen == nil)
		return;
	if(w.focused)
		col := w.display.color(bdfocused);
	else
		col = w.display.color(bdunfocused);
	i := w.screen.image;
	r := w.screen.image.r;
	i.draw((r.min, (r.min.x+w.bd, r.max.y)), col, nil, (0, 0));
	i.draw(((r.min.x+w.bd, r.min.y), (r.max.x, r.min.y+w.bd)), col, nil, (0, 0));
	i.draw(((r.max.x-w.bd, r.min.y+w.bd), r.max), col, nil, (0, 0));
	i.draw(((r.min.x+w.bd, r.max.y-w.bd), (r.max.x-w.bd, r.max.y)), col, nil, (0, 0));
}

inborder(w: ref Window, p: Point): int
{
	r := w.screen.image.r;
	return (Rect(r.min, (r.min.x+w.bd, r.max.y))).contains(p) ||
		(Rect((r.min.x+w.bd, r.min.y), (r.max.x, r.min.y+w.bd))).contains(p) ||
		(Rect((r.max.x-w.bd, r.min.y+w.bd), r.max)).contains(p) ||
		(Rect((r.min.x+w.bd, r.max.y-w.bd), (r.max.x-w.bd, r.max.y))).contains(p);
}

readscreenrect(w: ref Window)
{
	if((fd := sys->open("/chan/wmrect", Sys->OREAD)) != nil){
		buf := array[12*4] of byte;
		n := sys->read(fd, buf, len buf);
		if(n > 0){
			(w.displayr, nil) = s2r(string buf[0:n], 0);
			return;
		}
	}
	w.displayr = w.display.image.r;
}

Window.onscreen(w: self ref Window, how: string)
{
	if(how == nil)
		how = "place";
	w.wmctl(sys->sprint("!reshape . -1 %s %q", r2s(w.r), how));
}

Window.startinput(w: self ref Window, devs: list of string)
{
	for(; devs != nil; devs = tl devs)
		w.wmctl(sys->sprint("start %q", hd devs));
}

# commands originating both from tkclient and wm (via ctl)
Window.wmctl(w: self ref Window, req: string): string
{
	(c, next) := qword(req, 0);
	case c {
	"exit" =>
		sys->fprint(sys->open("/prog/" + string sys->pctl(0, nil) + "/ctl", Sys->OWRITE), "killgrp");
		exit;
	"rect" =>
		(w.displayr, nil) = s2r(req, next);
	"haskbdfocus" =>
		w.focused = int qword(req, next).t0;
		drawborder(w);
	"task" =>
		title := "";
		wmreq(w, sys->sprint("task %q", title), next);
		w.saved = w.r.min;
	"untask" =>
		wmreq(w, req, next);
	* =>
		return wmreq(w, req, next);
	}
	return nil;
}

wmreq(w: ref Window, req: string, e: int): string
{
	name: string;
	if(req != nil && req[0] == '!'){
		(name, e) = qword(req, e);
		if(name != ".")
			return "invalid window name";
	}
	if(w.ctxt.connfd != nil){
		if(sys->fprint(w.ctxt.connfd, "%s", req) == -1)
			return sys->sprint("%r");
		if(req[0] == '!')
			recvimage(w);
		return nil;
	}
	# if we're getting an image and there's no window manager,
	# then there's only one image to get...
	if(req[0] == '!')
		putimage(w, w.ctxt.ctxt.display.image);
	else{
		(nil, nil, err) := wmlib->wmctl(w.ctxt, req);
		return err;
	}
	return nil;
}

recvimage(w: ref Window)
{
	i := <-w.ctxt.images;
	if(i == nil)
		i = <-w.ctxt.images;
	putimage(w, i);
}

Window.settitle(nil: self ref Window, nil: string): string
{
	return nil;
}

snarfget(): string
{
	return wmlib->snarfget();
}

snarfput(buf: string)
{
	return wmlib->snarfput(buf);
}

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}
