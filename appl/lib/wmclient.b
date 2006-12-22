implement Wmclient;

#
# Copyright © 2003 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Image, Screen, Rect, Point, Pointer, Wmcontext, Context: import draw;
include "tk.m";
	tk: Tk;
	Toplevel: import tk;
include "wmlib.m";
	wmlib: Wmlib;
	qword, splitqword, s2r: import wmlib;
include "titlebar.m";
	titlebar: Titlebar;
include "wmclient.m";

Focusnone, Focusimage, Focustitle: con iota;

Bdup: con int 16rffffffff;
Bddown: con int 16radadadff;

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if(wmlib == nil){
		sys->fprint(sys->fildes(2), "wmclient: cannot load %s: %r\n", Wmlib->PATH);
		raise "fail:bad module";
	}
	wmlib->init();
	titlebar = load Titlebar Titlebar->PATH;
	if(titlebar == nil){
		sys->fprint(sys->fildes(2), "wmclient: cannot load %s: %r\n", Titlebar->PATH);
		raise "fail:bad module";
	}
	titlebar->init();
}

makedrawcontext(): ref Draw->Context
{
	return wmlib->makedrawcontext();
}

cursorspec(img: ref Draw->Image): string
{
	Hex: con "0123456789abcdef";
	if(img == nil || img.depth != 1)
		return "cursor";
	display := img.display;
	hot := img.r.min;
	if(img.r.min.x != 0 || img.r.min.y != 0){
		n := display.newimage(((0, 0), img.r.size()), Draw->GREY1, 0, Draw->Nofill);
		n.draw(n.r, img, nil, img.r.min);
		img = n;
	}
	s := sys->sprint("cursor %d %d %d %d ", hot.x, hot.y, img.r.dx(), img.r.dy());
	nb := img.r.dy() * draw->bytesperline(img.r, img.depth);
	buf := array[nb] of byte;
	if(img.readpixels(img.r, buf) == -1)
		return "cursor";

	for(i := 0; i < nb; i++){
		c := int buf[i];
		s[len s] = Hex[c >> 4];
		s[len s] = Hex[c & 16rf];
	}
	return s;
}
		
blankwin: Window;
window(ctxt: ref Draw->Context, title: string, buts: int): ref Window
{
	w := ref blankwin;
	w.ctxt = wmlib->connect(ctxt);
	w.display = ctxt.display;
	w.ctl = chan of string;
	readscreenrect(w);

	if(buts & Plain)
		return w;

	if(ctxt.wm == nil)
		buts &= ~(Resize|Hide);

	w.bd = 1;
	w.titlebar = tk->toplevel(ctxt.display, nil);
	top := w.titlebar;
	top.wreq = nil;

	w.ctl = titlebar->new(top, buts);
	titlebar->settitle(top, title);
	sizetb(w);
	w.wmctl("fixedorigin");
	return w;
}

Window.pointer(w: self ref Window, p: Draw->Pointer): int
{
	if(w.screen == nil || w.titlebar == nil)
		return 0;

	if(p.buttons && (w.ptrfocus == Focusnone || w.buttons == 0)){
		if(p.xy.in(w.tbrect))
			w.ptrfocus = Focustitle;
		else
			w.ptrfocus = Focusimage;
	}
	w.buttons = p.buttons;
	if(w.ptrfocus == Focustitle){
		tk->pointer(w.titlebar, p);
		return 1;
	}
	return 0;
}

# titlebar requested size might have changed:
# find out what size it's requesting.
sizetb(w: ref Window)
{
	if(w.titlebar == nil)
		return;
	w.tbsize = tk->rect(w.titlebar, ".", Tk->Border|Tk->Required).size();
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
	w.screen = Screen.allocate(i, w.display.color(Draw->White), 0);
	ir := i.r.inset(w.bd);
	if(ir.dx() < 0)
		ir.max.x = ir.min.x;
	if(ir.dy() < 0)
		ir.max.y = ir.min.y;
	if(w.titlebar != nil){
		w.tbrect = Rect(ir.min, (ir.max.x, ir.min.y + w.tbsize.y));
		tbimage := w.screen.newwindow(w.tbrect, Draw->Refnone, Draw->Nofill);
		tk->putimage(w.titlebar, ".", tbimage, nil);
		ir.min.y = w.tbrect.max.y;
	}
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
	if(w.titlebar != nil){
		if(r.dx() < w.tbsize.x)
			r.max.x = r.min.x + w.tbsize.x;
		r.min.y -= w.tbsize.y;
	}
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
	if(w.titlebar != nil){
		r.min.y += w.tbsize.y;
		if(r.dy() < 0)
			r.max.y = r.min.y;
	}
	return r;
}

# draw an imitation tk border.
drawborder(w: ref Window)
{
	if(w.screen == nil)
		return;
	col := w.display.color(Bdup);
	i := w.screen.image;
	r := w.screen.image.r;
	i.draw((r.min, (r.min.x+w.bd, r.max.y)), col, nil, (0, 0));
	i.draw(((r.min.x+w.bd, r.min.y), (r.max.x, r.min.y+w.bd)), col, nil, (0, 0));
	col = w.display.color(Bddown);
	i.draw(((r.max.x-w.bd, r.min.y+w.bd), r.max), col, nil, (0, 0));
	i.draw(((r.min.x+w.bd, r.max.y-w.bd), (r.max.x-w.bd, r.max.y)), col, nil, (0, 0));
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
	# old-style requests: pass them back around in proper form.
	"move" =>
		# move x y
		if(w.titlebar != nil)
			titlebar->sendctl(w.titlebar, "!move . -1 " + req[next:]);
	"size" =>
		if(w.titlebar != nil){
			minsz := titlebar->minsize(w.titlebar);
			titlebar->sendctl(w.titlebar, "!size . -1 " + string minsz.x + " " + string minsz.y);
		}
	"ok" or
	"help" =>
		;
	"rect" =>
		(w.displayr, nil) = s2r(req, next);
	"haskbdfocus" =>
		w.focused = int qword(req, next).t0;
		if(w.titlebar != nil){
			tk->cmd(w.titlebar, "focus -global " + string w.focused);
			tk->cmd(w.titlebar, "update");
		}
		drawborder(w);
	"task" =>
		title := "";
		if(w.titlebar != nil)
			title = titlebar->title(w.titlebar);
		wmreq(w, sys->sprint("task %q", title), next);
		w.saved = w.r.min;
		# send window out of the way
		# XXX oops, can't do this for plain windows...
		titlebar->sendctl(w.titlebar, "!reshape . -1 " + r2s((w.displayr.max, w.displayr.max.add(w.r.size()))));
	"untask" =>
		wmreq(w, req, next);
		# put window back where it was before.
		# XXX what do we we do if the window manager window has been reshape in the meantime...?
		titlebar->sendctl(w.titlebar, "!reshape . -1 " + r2s((w.saved, w.saved.add(w.r.size()))));
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

Window.settitle(w: self ref Window, title: string): string
{
	if(w.titlebar == nil)
		return nil;
	oldr := w.imager(w.r);
	old := titlebar->settitle(w.titlebar, title);
	sizetb(w);
	if(w.tbsize.x < w.r.dx())
		tk->putimage(w.titlebar, ".", w.titlebar.image, nil);	# unsuspend the window
	else
		w.wmctl("!reshape . -1 " + r2s(w.screenr(oldr)));
	return old;
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
