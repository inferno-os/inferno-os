implement Tkclient;

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
include "tkclient.m";

Background: con int 16r777777FF;		# should be drawn over immediately, but just in case...

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if(wmlib == nil){
		sys->fprint(sys->fildes(2), "tkclient: cannot load %s: %r\n", Wmlib->PATH);
		raise "fail:bad module";
	}
	wmlib->init();
	titlebar = load Titlebar Titlebar->PATH;
	if(titlebar == nil){
		sys->fprint(sys->fildes(2), "tkclient: cannot load %s: %r\n", Titlebar->PATH);
		raise "fail:bad module";
	}
	titlebar->init();
}

makedrawcontext(): ref Draw->Context
{
	return wmlib->makedrawcontext();
}

toplevel(ctxt: ref Draw->Context, topconfig: string, title: string, buts: int): (ref Tk->Toplevel, chan of string)
{
	wm := wmlib->connect(ctxt);
	opts := "";
	if((buts & Plain) == 0)
		opts = "-borderwidth 1 -relief raised ";
	top := tk->toplevel(wm.ctxt.display, opts+topconfig);
	if (top == nil) {
		sys->fprint(sys->fildes(2), "wmlib: window creation failed (top %ux, i %ux)\n", top, top.image);
		raise "fail:window creation failed";
	}
	top.ctxt = wm;
	readscreenrect(top);
	c := titlebar->new(top, buts);
	titlebar->settitle(top, title);
	return (top, c);
}

readscreenrect(top: ref Tk->Toplevel)
{
	if((fd := sys->open("/chan/wmrect", Sys->OREAD)) != nil){
		buf := array[12*4] of byte;
		n := sys->read(fd, buf, len buf);
		if(n > 0)
			(top.screenr, nil) = s2r(string buf[0:n], 0);
	}
}

onscreen(top: ref Tk->Toplevel, how: string)
{
	if(how == nil)
		how = "place";
	wmctl(top, sys->sprint("!reshape . -1 %s %q",
			r2s(tk->rect(top, ".", Tk->Border|Tk->Required)), how));
}

startinput(top: ref Tk->Toplevel, devs: list of string)
{
	for(; devs != nil; devs = tl devs)
		wmctl(top, sys->sprint("start %q", hd devs));
}

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

# commands originating both from tkclient and wm (via ctl)
wmctl(top: ref Tk->Toplevel, req: string): string
{
#sys->print("wmctl %s\n", req);
	(c, next) := qword(req, 0);
	case c {
	"exit" =>
		sys->fprint(sys->open("/prog/" + string sys->pctl(0, nil) + "/ctl", Sys->OWRITE), "killgrp");
		exit;
	# old-style requests: pass them back around in proper form.
	"move" =>
		# move x y
		titlebar->sendctl(top, "!move . -1 " + req[next:]);
	"size" =>
		minsz := titlebar->minsize(top);
		titlebar->sendctl(top, "!size . -1 " + string minsz.x + " " + string minsz.y);
	"ok" or
	"help" =>
		;
	"rect" =>
		r: Rect;
		(c, next) = qword(req, next);
		r.min.x = int c;
		(c, next) = qword(req, next);
		r.min.y = int c;
		(c, next) = qword(req, next);
		r.max.x = int c;
		(c, next) = qword(req, next);
		r.max.y = int c;
		top.screenr = r;
	"haskbdfocus" =>
		in := int qword(req, next).t0 != 0;
		cmd(top, "focus -global " + string in);
		cmd(top, "update");
	"task" =>
		(r, nil) := splitqword(req, next);
		if(r.t0 == r.t1)
			req = sys->sprint("task %q", cmd(top, ".Wm_t.title cget -text"));
		if(wmreq(top, c, req, next) == nil)
			cmd(top, ". unmap; update");
	"untask" =>
		cmd(top, ". map; update");
		return wmreq(top, c, req, next);
	* =>
		return wmreq(top, c, req, next);
	}
	return nil;
}

wmreq(top: ref Tk->Toplevel, c, req: string, e: int): string
{
	err := wmreq1(top, c, req, e);
#	if(err != nil)
#		sys->fprint(sys->fildes(2), "tkclient: request %#q failed: %s\n", req, err);
	return err;
}

wmreq1(top: ref Tk->Toplevel, c, req: string, e: int): string
{
	name, reqid: string;
	if(req != nil && req[0] == '!'){
		(name, e) = qword(req, e);
		(reqid, e) = qword(req, e);
		if(name == nil || reqid == nil)
			return "bad arg count";
	}
	if(top.ctxt.connfd != nil){
		if(sys->fprint(top.ctxt.connfd, "%s", req) == -1)
			return sys->sprint("%r");
		if(req[0] == '!')
			recvimage(top, name, reqid);
		return nil;
	}
	if(req[0] != '!'){
		(nil, nil, err) := wmlib->wmctl(top.ctxt, req);
		return err;
	}
	# if there's no window manager, then we create a screen on the
	# display image. there's nowhere to find the screen again except
	# through the toplevel's image. that means that you can't create a
	# menu without mapping a toplevel, and if you manage to unmap
	# the toplevel without unmapping the menu, you'll have two
	# screens on the same display image
	# in the image, so
	if(c != "!reshape")
		return "unknown request";
	i: ref Image;
	if(top.image == nil){
		if(name != ".")
			return "screen not available";
		di := top.display.image;
		screen := Screen.allocate(di, top.display.color(Background), 0);
		di.draw(di.r, screen.fill, nil, screen.fill.r.min);
		i = screen.newwindow(di.r, Draw->Refbackup, Draw->Nofill);
	}else{
		if(name == ".")
			i = top.image;
		else
			i = top.image.screen.newwindow(s2r(req, e).t0, Draw->Refbackup, Draw->Red);
	}
	tk->putimage(top, name+" "+reqid, i, nil);
	return nil;
}

recvimage(top: ref Tk->Toplevel, name, reqid: string)
{
	i := <-top.ctxt.images;
	if(i == nil){
		cmd(top, name + " suspend");
		i = <-top.ctxt.images;
	}
	tk->putimage(top, name+" "+reqid, i, nil);
}

settitle(top: ref Tk->Toplevel, name: string): string
{
	return titlebar->settitle(top, name);
}

handler(top: ref Tk->Toplevel, stop: chan of int)
{
	ctxt := top.ctxt;
	if(stop == nil)
		stop = chan of int;
	for(;;)alt{
	c := <-ctxt.kbd =>
		tk->keyboard(top, c);
	p := <-ctxt.ptr =>
		tk->pointer(top, *p);
	c := <-ctxt.ctl or
	c = <-top.wreq =>
		wmctl(top, c);
	<-stop =>
		exit;
	}
}

snarfget(): string
{
	return wmlib->snarfget();
}

snarfput(buf: string)
{
	return wmlib->snarfput(buf);
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "tkclient: tk error %s on '%s'\n", e, s);
	return e;
}

