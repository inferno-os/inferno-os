implement Pen;

#
# pen input on touch screen
#
#	Copyright © 2001,2002 Vita Nuova Holdings Limited.  All rights reserved.
#
#	This may be used or modified by anyone for any purpose.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Point, Rect: import draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "strokes.m";
	strokes: Strokes;
	Classifier, Penpoint, Stroke: import strokes;
	readstrokes: Readstrokes;

include "arg.m";

Pen: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

debug := 0;
stderr: ref Sys->FD;

tkconfig := array[] of{
	"canvas .c -borderwidth 0 -bg white -height 80 -width 80",
	".c create text 0 0 -anchor nw -width 5w -fill gray -tags mode",
	".c create text 30 0 -anchor nw -width 3w -fill blue -tags char",
	"bind .c <Button-1> {grab set .c; send cmd push %x %y}",
	"bind .c <Motion-Button-1> {send cmd move %x %y}",
	"bind .c <ButtonRelease-1> {grab release .c; send cmd release %x %y}",
	"bind .c <Enter> {send cmd move %x %y}",	# does nothing if not previously down
#	"bind .c <Leave> {send cmd leave %x %y}",	# ditto
	"pack .c -expand 1 -fill both -padx 5 -pady 5",
};

usage()
{
	sys->fprint(sys->fildes(2), "Usage: pen [-t] [-e] [classifier ...]\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "pen: no window context\n");
		raise "fail:bad context";
	}
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	tk = load Tk Tk->PATH;
	if(tk == nil)
		nomod(Tk->PATH);
	tkclient = load Tkclient Tkclient->PATH;
	if(tkclient == nil)
		nomod(Tkclient->PATH);
	strokes = load Strokes Strokes->PATH;
	if(strokes == nil)
		nomod(Strokes->PATH);
	strokes->init();
	readstrokes = load Readstrokes Readstrokes->PATH;
	if(readstrokes == nil)
		nomod(Readstrokes->PATH);
	readstrokes->init(strokes);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);
	taskbar := 0;
	noexit := 0;
	winopts := Tkclient->Appl;
	corner := 1;
	while((opt := arg->opt()) != 0)
		case opt {
		't' =>
			taskbar = 1;
		'e' =>
			noexit = 1;
		'r' =>
			winopts &= ~Tkclient->Resize;
		'c' =>
			corner = 0;
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;

	if(args == nil)
		args = "/lib/strokes/letters.clx" :: "/lib/strokes/digits.clx" :: "/lib/strokes/punc.clx" :: nil;
	csets := array[len args] of ref Classifier;
	cs := 0;
	for(; args != nil; args = tl args){
		file := hd args;
		(err, rc) := readstrokes->read_classifier(file, 1, 0);
		if(rc == nil)
			error(sys->sprint("can't read classifier %s: %s", file, err));
		csets[cs++] = rc;
	}
	readstrokes = nil;

	rec := csets[0];
	digits: ref Classifier;
	if(len csets > 1)
		digits = csets[1];	# need not actually be digits

	sys->pctl(Sys->NEWPGRP, nil);
	tkclient->init();
	(top, ctl) := tkclient->toplevel(ctxt, nil, "Pen", winopts);
	cmd := chan of string;
	tk->namechan(top, cmd, "cmd");
	for (i1 := 0; i1 < len tkconfig; i1++)
		tkcmd(top, tkconfig[i1]);
	if(winopts & Tkclient->Resize)
		tkcmd(top, "pack propagate . 0");


	if(corner){
		(w, h) := (int tk->cmd(top, ". cget -width"), int tk->cmd(top, ". cget -height"));
		r := ctxt.display.image.r;
		tkcmd(top, sys->sprint(". configure -x %d -y %d", r.max.x-w, r.max.y-h));
	}


	shift := 0;
	punct := 0;
	points := array[1000] of Penpoint;
	npoint := 0;

	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "ptr"::nil);
	if(taskbar)
		tkclient->wmctl(top, "task");
	tk->cmd(top, "update");

	for(;;){
		if(punct)
			drawmode(top, "#&*");
		else if(rec == digits)
			drawmode(top, "123");
		else if(shift == 1)
			drawmode(top, "Abc");
		else if(shift == 2)
			drawmode(top, "ABC");
		else if(shift)
			drawmode(top, "S "+string shift);
		else
			drawmode(top, "abc");
		tk->cmd(top, "update");
		alt{
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);

		s := <-top.ctxt.ctl or
		s = <-top.wreq or
		s = <-ctl =>
			if(s == "exit" && noexit)
				s = "task";
			tkclient->wmctl(top, s);

		s := <-cmd =>
			(nf, flds) := sys->tokenize(s, " \t");
			if(nf < 3)
				break;
			p := Penpoint(int hd tl flds, int hd tl tl flds, 0);
			case hd flds {
			"push" =>
				tkcmd(top, "raise .");
				tk->cmd(top, "update");
				npoint = 0;
				points[npoint++] = p;
			"leave" =>
				npoint = 0;
				tkcmd(top, ".c delete stuff");
			"release" =>
				if(npoint == 0)
					break;
				points[npoint++] = p;
				(n, tap) := recognize_stroke(top, rec, ref Stroke(npoint, points[0:npoint], 0, 0), debug);
				drawchars(top, "");
				name: string = nil;
				if(n >= 0){
					name = rec.cnames[n];
					if(debug > 1){
						ex: ref Stroke = nil;
						if(rec.canonex != nil)
							ex = rec.canonex[n];
						drawshape(top, "stuff", ex, "blue", rec.dompts[n], "yellow");
						sys->fprint(stderr, "match: %s\n", name);
					}
					case c := name[0] {
					'S' =>
						shift = (shift+1)%3;
						name = nil;
					'A' =>
						name = " ";
					'B' =>
						name = "\b";
					'R' =>
						name = "\n";
					'T' =>
						name = "\t";
					'N' =>
						# num lock
						if(rec == digits)
							rec = csets[0];
						else
							rec = digits;
						name = nil;
					* =>
						if(c >= 'A' && c <= 'Z'){	# other gestures, not yet implemented
							shift = 0;
							punct = 0;
							rec = csets[0];
							name = nil;
							unknown(top);
							break;
						}
						if(punct){
							rec = csets[0];
							punct = 0;
						}
						if(shift){
							for(i := 0; i < len name; i++)
								if((c = name[i]) >= 'a' && c <= 'z')
									name[i] += 'A'-'a';
							if(shift < 2)
								shift = 0;
						}
					}
				}else if(tap != nil){
					if(punct == 0){
						if(len csets > 2){
							rec = csets[2];
							punct = 1;
						}
						name = nil;
					}else{
						rec = csets[0];
						punct = 0;
						name = ".";
					}
				}else
					unknown(top);
				if(name != nil){
					drawchars(top, name);
					for(i := 0; i < len name; i++)
						sys->fprint(top.ctxt.connfd, "key %d", name[i]);
					#	tk->keyboard(top, name[i]);
				}
				tkcmd(top, ".c delete stuff");
				npoint = 0;
			* =>
				if(npoint){
					q := points[npoint-1];
					points[npoint++] = p;
					tkcmd(top, sys->sprint(".c create line %d %d %d %d -tags stuff; update", q.x, q.y, p.x, p.y));
				}
			}
		}
	}
}

unknown(top: ref Tk->Toplevel)
{
	drawquery(top, (10, 10), 3);
	tk->cmd(top, "update");
	sys->sleep(300);
	tkcmd(top, ".c delete query");
	tk->cmd(top, "update");
}

drawchars(top: ref Tk->Toplevel, s: string)
{
	t := "";
	for(i := 0; i < len s; i++){
		c := s[i];
		case c {
		'\n' =>	t += "\\n";
		'\b' =>	t += "\\b";
		'\t' =>	t += "\\t";
		4 =>		t += "eot";
		* =>
			if(c < ' ')
				t += sys->sprint("\\%3.3o", c);
			else
				t[len t] = c;
		}
	}
	tkcmd(top, ".c itemconfigure char -text '"+t);
}
		
drawmode(top: ref Tk->Toplevel, mode: string)
{
	tkcmd(top, ".c itemconfigure mode -text '"+mode);
}

drawquery(top: ref Tk->Toplevel, p: Point, scale: int)
{
	width := 2;
	size := 1<<scale;
	if(size < 4)
		width = 1;
	o := Point(p.x-size/2, p.x+size/2);
	if(o.x < 0)
		o.x = 0;
	if(o.y < 0)
		o.y = 0;
	c := o.add((size, size));
	m := o.add(c).div(2);
	b := c.add((0, size));
	tkcmd(top, sys->sprint(".c create arc %d %d %d %d -start 150 -extent -240 -style arc -tags query -width %d -outline red", o.x, o.y, c.x, c.y, width));
	tkcmd(top, sys->sprint(".c create line %d %d %d %d -fill red -width %d -tags query", m.x, c.y, m.x, b.y, width));
	tkcmd(top, sys->sprint(".c create arc %d %d %d %d -start 0 -extent 360 -fill red -width %d -tags query -style arc -outline red", m.x-width, b.y+2*width, m.x+width, b.y+3*width, width));
}

tkcmd(top: ref Tk->Toplevel, s: string)
{
	e := tk->cmd(top, s);
	if(e != nil && e[0]=='!')
		sys->fprint(sys->fildes(2), "pen: tk error: %s in [%s]\n", e, s);
}

drawshape(top: ref Tk->Toplevel, tag: string, stroke: ref Stroke, colour: string, dompts: ref Stroke, domcol: string)
{
	if(top == nil)
		return;
	if(stroke != nil)
		for(i := 1; i < stroke.npts; i++){
			p := stroke.pts[i-1];
			q := stroke.pts[i];
			tkcmd(top, sys->sprint(".c create line %d %d %d %d -fill %s -tags %s", p.x, p.y, q.x, q.y, colour, tag));
		}
	if(dompts != nil)
		for(i = 0; i < dompts.npts; i++){
			p := dompts.pts[i];
			tkcmd(top, sys->sprint(".c create oval %d %d %d %d -fill %s -tags %s", p.x-1, p.y-1, p.x+1, p.y+1, domcol, tag));
		}
	tk->cmd(top, "update");
}

#
# duplicate function of strokes module temporarily
# to allow for experiment
#

#DIST_THLD: con 3200;	# x100
DIST_THLD: con 3300;	# x100

#  Tap-handling parameters
TAP_TIME_THLD: con 150;	# msec
TAP_DIST_THLD: con 75;		# dx*dx + dy*dy
TAP_PATHLEN: con 10*100;		# x100

recognize_stroke(top: ref Tk->Toplevel, rec: ref Classifier, stroke: ref Stroke, debug: int): (int, string)
{

	if(stroke.npts < 1)
		return (-1, nil);

	stroke = stroke.filter();	 # filter out close points

	if(stroke.npts == 1 || stroke.length() < TAP_PATHLEN)
		return (-1, ".");		# considered a tap regardless of elapsed time

	strokes->preprocess_stroke(stroke);

	#  Compute its dominant points.
	dompts := stroke.interpolate().dominant();

	if(debug)
		drawshape(top, "stuff", stroke, "green", dompts, "red");

	if(rec == nil)
		return (-1, nil);

	best_dist := Strokes->MAXDIST;
	best_i := -1;

	#  Score input stroke against every class in classifier.
	for(i := 0; i < rec.nclasses; i++){
		name := rec.cnames[i];
		(sim, dist) := strokes->score_stroke(dompts, rec.dompts[i]);
		if(debug > 1 && dist < Strokes->MAXDIST)
			sys->fprint(stderr, "(%s, %d, %d) ", name, sim, dist);
		if(dist < DIST_THLD){
			if(debug > 1)
				sys->fprint(stderr, "(%s, %d, %d) ", name, sim, dist);
			#  Is it the best so far?
			if(dist < best_dist){
				best_dist = dist;
				best_i = i;
			}
		}
	}

	if(debug > 1)
		sys->fprint(stderr, "\n");

	return (best_i, nil);
}

objrect(t: ref Tk->Toplevel, path: string, addbd: int): Rect
{
	r: Rect;
	r.min.x = int tk->cmd(t, path+" cget -actx");
	if(addbd)
		r.min.x += int tk->cmd(t, path+" cget -bd");
	r.min.y = int tk->cmd(t, ".f cget -acty");	
	if(addbd)
		r.min.y += int tk->cmd(t, path+" cget -bd");
	r.max.x = r.min.x + int tk->cmd(t, path+" cget -actwidth");
	r.max.y = r.min.y + int tk->cmd(t, path+" cget -actheight");
	return r;
}

nomod(s: string)
{
	error(sys->sprint("can't load %s: %r", s));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "scribble: %s\n", s);
	raise "fail:error";
}
