implement Wm;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Screen, Display, Image, Rect, Point, Wmcontext, Pointer: import draw;
include "wmsrv.m";
	wmsrv: Wmsrv;
	Window, Client: import wmsrv;
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
include "string.m";
	str: String;
include "sh.m";
include "winplace.m";
	winplace: Winplace;

Wm: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Ptrstarted, Kbdstarted, Controlstarted, Controller, Fixedorigin: con 1<<iota;
Bdwidth: con 3;
Sminx, Sminy, Smaxx, Smaxy: con iota;
Minx, Miny, Maxx, Maxy: con 1<<iota;
Background: con int 16r777777FF;

screen: ref Screen;
display: ref Display;
ptrfocus: ref Client;
kbdfocus: ref Client;
controller: ref Client;
allowcontrol := 1;
fakekbd: chan of string;
fakekbdin: chan of string;
buttons := 0;

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "wm: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys  = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	if(draw == nil)
		badmodule(Draw->PATH);

	str = load String String->PATH;
	if(str == nil)
		badmodule(String->PATH);

	wmsrv = load Wmsrv Wmsrv->PATH;
	if(wmsrv == nil)
		badmodule(Wmsrv->PATH);

	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil)
		badmodule(Wmclient->PATH);
	wmclient->init();

	winplace = load Winplace Winplace->PATH;
	if(winplace == nil)
		badmodule(Winplace->PATH);
	winplace->init();

	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	if (ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	display = ctxt.display;

	buts := Wmclient->Appl;
	if(ctxt.wm == nil)
		buts = Wmclient->Plain;
	win := wmclient->window(ctxt, "Wm", buts);
	wmclient->win.reshape(((0, 0), (100, 100)));
	wmclient->win.onscreen("place");
	if(win.image == nil){
		sys->fprint(sys->fildes(2), "wm: cannot get image to draw on\n");
		raise "fail:no image";
	}
	wmclient->win.startinput("kbd" :: "ptr" :: nil);

	wmctxt := win.ctxt;
	screen = makescreen(win.image);

	(clientwm, join, req) := wmsrv->init();
	clientctxt := ref Draw->Context(ctxt.display, nil, clientwm);

	wmrectIO := sys->file2chan("/chan", "wmrect");
	if(wmrectIO == nil)
		fatal(sys->sprint("cannot make /chan/wmrect: %r"));

	sync := chan of string;
	argv = tl argv;
	if(argv == nil)
		argv = "wm/toolbar" :: nil;
	spawn command(clientctxt, argv, sync);
	if((e := <-sync) != nil)
		fatal("cannot run command: " + e);

	fakekbd = chan of string;
	for(;;) alt {
	c := <-win.ctl or
	c = <-wmctxt.ctl =>
		# XXX could implement "pleaseexit" in order that
		# applications can raise a warning message before
		# they're unceremoniously dumped.
		if(c == "exit")
			for(z := wmsrv->top(); z != nil; z = z.znext)
				z.ctl <-= "exit";

		wmclient->win.wmctl(c);
		if(win.image != screen.image)
			reshaped(win);
	c := <-wmctxt.kbd or
	c = int <-fakekbd =>
		if(kbdfocus != nil)
			kbdfocus.kbd <-= c;
	p := <-wmctxt.ptr =>
		if(wmclient->win.pointer(*p))
			break;
		if(p.buttons && (ptrfocus == nil || buttons == 0)){
			c := wmsrv->find(p.xy);
			if(c != nil){
				ptrfocus = c;
				c.ctl <-= "raise";
				setfocus(win, c);
			}
		}
		if(ptrfocus != nil && (ptrfocus.flags & Ptrstarted) != 0){
			# inside currently selected client or it had button down last time (might have come up)
			buttons = p.buttons;
			ptrfocus.ptr <-= p;
			break;
		}
		buttons = 0;
	(c, rc) := <-join =>
		rc <-= nil;
		# new client; inform it of the available screen rectangle.
		# XXX do we need to do this now we've got wmrect?
		c.ctl <-= "rect " + r2s(screen.image.r);
		if(allowcontrol){
			controller = c;
			c.flags |= Controller;
			allowcontrol = 0;
		}else
			controlevent("newclient " + string c.id);
		c.cursor = "cursor";
	(c, data, rc) := <-req =>
		# if client leaving
		if(rc == nil){
			c.remove();
			if(c == ptrfocus)
				ptrfocus = nil;
			if(c == kbdfocus)
				kbdfocus = nil;
			if(c == controller)
				controller = nil;
			controlevent("delclient " + string c.id);
			for(z := wmsrv->top(); z != nil; z = z.znext)
				if(z.flags & Kbdstarted)
					break;
			setfocus(win, z);
			c.stop <-= 1;
			break;
		}
		err := handlerequest(win, wmctxt, c, string data);
		n := len data;
		if(err != nil)
			n = -1;
		alt{
		rc <-= (n, err) =>;
		* =>;
		}
	(nil, nil, nil, wc) := <-wmrectIO.write =>
		if(wc == nil)
			break;
		alt{
		wc <-= (0, "cannot write") =>;
		* =>;
		}
	(off, nil, nil, rc) := <-wmrectIO.read =>
		if(rc == nil)
			break;
		d := array of byte r2s(screen.image.r);
		if(off > len d)
			off = len d;
		alt{
		rc <-= (d[off:], nil) =>;
		* =>;
		}
	}
}

handlerequest(win: ref Wmclient->Window, wmctxt: ref Wmcontext, c: ref Client, req: string): string
{
#sys->print("%d: %s\n", c.id, req);
	args := str->unquoted(req);
	if(args == nil)
		return "no request";
	n := len args;
	if(req[0] == '!' && n < 3)
		return "bad arg count";
	case hd args {
	"key" =>
		# XXX should we restrict this capability to certain clients only?
		if(n != 2)
			return "bad arg count";
		if(fakekbdin == nil){
			fakekbdin = chan of string;
			spawn bufferproc(fakekbdin, fakekbd);
		}
		fakekbdin <-= hd tl args;
	"ptr" =>
		# ptr x y
		if(n != 3)
			return "bad arg count";
		if(ptrfocus != c)
			return "cannot move pointer";
		e := wmclient->win.wmctl(req);
		if(e == nil){
			c.ptr <-= nil;		# flush queue
			c.ptr <-= ref Pointer(buttons, (int hd tl args, int hd tl tl args), sys->millisec());
		}
	"cursor" =>
		# cursor hotx hoty dx dy data
		if(n != 6 && n != 1)
			return "bad arg count";
		c.cursor = req;
		if(ptrfocus == c || kbdfocus == c)
			return wmclient->win.wmctl(c.cursor);
	"start" =>
		if(n != 2)
			return "bad arg count";
		case hd tl args {
		"mouse" or
		"ptr" =>
			c.flags |= Ptrstarted;
		"kbd" =>
			c.flags |= Kbdstarted;
			# XXX this means that any new window grabs the focus from the current
			# application, but usually you want this to happen... how can we distinguish
			# the two cases?
			setfocus(win, c);
		"control" =>
			if((c.flags & Controller) == 0)
				return "control not available";
			c.flags |= Controlstarted;
		* =>
			return "unknown input source";
		}
	"!reshape" =>
		# reshape tag reqid rect [how]
		# XXX allow "how" to specify that the origin of the window is never
		# changed - a new window will be created instead.
		if(n < 7)
			return "bad arg count";
		args = tl args;
		tag := hd args; args = tl args;
		args = tl args;		# skip reqid
		r: Rect;
		r.min.x = int hd args; args = tl args;
		r.min.y = int hd args; args = tl args;
		r.max.x = int hd args; args = tl args;
		r.max.y = int hd args; args = tl args;
		if(args != nil){
			case hd args{
			"onscreen" =>
				r = fitrect(r, screen.image.r);
			"place" =>
				r = fitrect(r, screen.image.r);
				r = newrect(r, screen.image.r);
			"exact" =>
				;
			"max" =>
				r = screen.image.r;			# XXX don't obscure toolbar?
			* =>
				return "unkown placement method";
			}
		}
		return reshape(c, tag, r);
	"delete" =>
		# delete tag
		if(tl args == nil)
			return "tag required";
		c.setimage(hd tl args, nil);
		if(c.wins == nil && c == kbdfocus)
			setfocus(win, nil);
	"raise" =>
		c.top();
	"lower" =>
		c.bottom();
	"!move" or
	"!size" =>
		# !move tag reqid startx starty
		# !size tag reqid mindx mindy
		ismove := hd args == "!move";
		if(n < 3)
			return "bad arg count";
		args = tl args;
		tag := hd args; args = tl args;
		args = tl args;			# skip reqid
		w := c.window(tag);
		if(w == nil)
			return "no such tag";
		if(ismove){
			if(n != 5)
				return "bad arg count";
			return dragwin(wmctxt.ptr, c, w, Point(int hd args, int hd tl args).sub(w.r.min));
		}else{
			if(n != 5)
				return "bad arg count";
			sizewin(wmctxt.ptr, c, w, Point(int hd args, int hd tl args));
		}
	"fixedorigin" =>
		c.flags |= Fixedorigin;
	"rect" =>
		;
	"kbdfocus" =>
		if(n != 2)
			return "bad arg count";
		if(int hd tl args)
			setfocus(win, c);
		else if(c == kbdfocus)
			setfocus(win, nil);
	# controller specific messages:
	"request" =>		# can be used to test for control.
		if((c.flags & Controller) == 0)
			return "you are not in control";
	"ctl" =>
		# ctl id msg
		if((c.flags & Controlstarted) == 0)
			return "invalid request";
		if(n < 3)
			return "bad arg count";
		id := int hd tl args;
		for(z := wmsrv->top(); z != nil; z = z.znext)
			if(z.id == id)
				break;
		if(z == nil)
			return "no such client";
		z.ctl <-= str->quoted(tl tl args);
	"endcontrol" =>
		if(c != controller)
			return "invalid request";
		controller = nil;
		allowcontrol = 1;
		c.flags &= ~(Controlstarted | Controller);
	* =>
		if(c == controller || controller == nil || (controller.flags & Controlstarted) == 0)
			return "unknown control request";
		controller.ctl <-= "request " + string c.id + " " + req;
	}
	return nil;
}

Fix: con 1000;
# the window manager window has been reshaped;
# allocate a new screen, and move all the 
reshaped(win: ref Wmclient->Window)
{
	oldr := screen.image.r;
	newr := win.image.r;
	mx := Fix;
	if(oldr.dx() > 0)
		mx = newr.dx() * Fix / oldr.dx();
	my := Fix;
	if(oldr.dy() > 0)
		my = newr.dy() * Fix / oldr.dy();
	screen = makescreen(win.image);
	for(z := wmsrv->top(); z != nil; z = z.znext){
		for(wl := z.wins; wl != nil; wl = tl wl){
			w := hd wl;
			w.img = nil;
			nr := w.r.subpt(oldr.min);
			nr.min.x = nr.min.x * mx / Fix;
			nr.min.y = nr.min.y * my / Fix;
			nr.max.x = nr.max.x * mx / Fix;
			nr.max.y = nr.max.y * my / Fix;
			nr = nr.addpt(newr.min);
			w.img = screen.newwindow(nr, Draw->Refbackup, Draw->Nofill);
			# XXX check for creation failure
			w.r = nr;
			z.ctl <-= sys->sprint("!reshape %q -1 %s", w.tag, r2s(nr));
			z.ctl <-= "rect " + r2s(newr);
		}
	}
}

controlevent(e: string)
{
	if(controller != nil && (controller.flags & Controlstarted))
		controller.ctl <-= e;
}

dragwin(ptr: chan of ref Pointer, c: ref Client, w: ref Window, off: Point): string
{
	if(buttons == 0)
		return "too late";
	p: ref Pointer;
	scr := screen.image.r;
	Margin: con 10;
	do{
		p = <-ptr;
		org := p.xy.sub(off);
		if(org.y < scr.min.y)
			org.y = scr.min.y;
		else if(org.y > scr.max.y - Margin)
			org.y = scr.max.y - Margin;
		if(org.x < scr.min.x && org.x + w.r.dx() < scr.min.x + Margin)
			org.x = scr.min.x + Margin - w.r.dx();
		else if(org.x > scr.max.x - Margin)
			org.x = scr.max.x - Margin;
		w.img.origin(w.img.r.min, org);
	} while (p.buttons != 0);
	c.ptr <-= p;
	buttons = 0;
	r: Rect;
	r.min = p.xy.sub(off);
	r.max = r.min.add(w.r.size());
	if(r.eq(w.r))
		return "not moved";
	reshape(c, w.tag, r);
	return nil;
}

sizewin(ptrc: chan of ref Pointer, c: ref Client, w: ref Window, minsize: Point): string
{
	borders := array[4] of ref Image;
	showborders(borders, w.r, Minx|Maxx|Miny|Maxy);
	screen.image.flush(Draw->Flushnow);
	while((ptr := <-ptrc).buttons == 0)
		;
	xy := ptr.xy;
	move, show: int;
	offset := Point(0, 0);
	r := w.r;
	show = Minx|Miny|Maxx|Maxy;
	if(xy.in(w.r) == 0){
		r = (xy, xy);
		move = Maxx|Maxy;
	}else {
		if(xy.x < (r.min.x+r.max.x)/2){
			move=Minx;
			offset.x = xy.x - r.min.x;
		}else{
			move=Maxx;
			offset.x = xy.x - r.max.x;
		}
		if(xy.y < (r.min.y+r.max.y)/2){
			move |= Miny;
			offset.y = xy.y - r.min.y;
		}else{
			move |= Maxy;
			offset.y = xy.y - r.max.y;
		}
	}
	return reshape(c, w.tag, sweep(ptrc, r, offset, borders, move, show, minsize));
}

reshape(c: ref Client, tag: string, r: Rect): string
{
	w := c.window(tag);
	# if window hasn't changed size, then just change its origin and use the same image.
	if((c.flags & Fixedorigin) == 0 && w != nil && w.r.size().eq(r.size())){
		c.setorigin(tag, r.min);
	} else {
		img := screen.newwindow(r, Draw->Refbackup, Draw->Nofill);
		if(img == nil)
			return sys->sprint("window creation failed: %r");
		if(c.setimage(tag, img) == -1)
			return "can't do two at once";
	}
	c.top();
	return nil;
}

sweep(ptr: chan of ref Pointer, r: Rect, offset: Point, borders: array of ref Image, move, show: int, min: Point): Rect
{
	while((p := <-ptr).buttons != 0){
		xy := p.xy.sub(offset);
		if(move&Minx)
			r.min.x = xy.x;
		if(move&Miny)
			r.min.y = xy.y;
		if(move&Maxx)
			r.max.x = xy.x;
		if(move&Maxy)
			r.max.y = xy.y;
		showborders(borders, r, show);
	}
	r = r.canon();
	if(r.min.y < screen.image.r.min.y){
		r.min.y = screen.image.r.min.y;
		r = r.canon();
	}
	if(r.dx() < min.x){
		if(move & Maxx)
			r.max.x = r.min.x + min.x;
		else
			r.min.x = r.max.x - min.x;
	}
	if(r.dy() < min.y){
		if(move & Maxy)
			r.max.y = r.min.y + min.y;
		else {
			r.min.y = r.max.y - min.y;
			if(r.min.y < screen.image.r.min.y){
				r.min.y = screen.image.r.min.y;
				r.max.y = r.min.y + min.y;
			}
		}
	}
	return r;
}

showborders(b: array of ref Image, r: Rect, show: int)
{
	r = r.canon();
	b[Sminx] = showborder(b[Sminx], show&Minx,
		(r.min, (r.min.x+Bdwidth, r.max.y)));
	b[Sminy] = showborder(b[Sminy], show&Miny,
		((r.min.x+Bdwidth, r.min.y), (r.max.x-Bdwidth, r.min.y+Bdwidth)));
	b[Smaxx] = showborder(b[Smaxx], show&Maxx,
		((r.max.x-Bdwidth, r.min.y), (r.max.x, r.max.y)));
	b[Smaxy] = showborder(b[Smaxy], show&Maxy,
		((r.min.x+Bdwidth, r.max.y-Bdwidth), (r.max.x-Bdwidth, r.max.y)));
}

showborder(b: ref Image, show: int, r: Rect): ref Image
{
	if(!show)
		return nil;
	if(b != nil && b.r.size().eq(r.size()))
		b.origin(r.min, r.min);
	else
		b = screen.newwindow(r, Draw->Refbackup, Draw->Red);
	return b;
}

r2s(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}

# XXX for consideration:
# do not allow applications to grab the keyboard focus
# unless there is currently no keyboard focus...
# but what about launching a new app from the taskbar:
# surely we should allow that to grab the focus?
setfocus(win: ref Wmclient->Window, new: ref Client)
{
	old := kbdfocus;
	if(old == new)
		return;
	if(new == nil)
		wmclient->win.wmctl("cursor");
	else if(old == nil || old.cursor != new.cursor)
		wmclient->win.wmctl(new.cursor);
	if(new != nil && (new.flags & Kbdstarted) == 0)
		return;
	if(old != nil)
		old.ctl <-= "haskbdfocus 0";
	
	if(new != nil){
		new.ctl <-= "raise";
		new.ctl <-= "haskbdfocus 1";
		kbdfocus = new;
	} else
		kbdfocus = nil;
}

makescreen(img: ref Image): ref Screen
{
	screen = Screen.allocate(img, img.display.color(Background), 0);
	img.draw(img.r, screen.fill, nil, screen.fill.r.min);
	return screen;
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "wm: %s\n", s);
	kill(sys->pctl(0, nil), "killgrp");
	raise "fail:error";
}

# fit a window rectangle to the available space.
# try to preserve requested location if possible.
# make sure that the window is no bigger than
# the screen, and that its top and left-hand edges
# will be visible at least.
fitrect(w, r: Rect): Rect
{
	if(w.dx() > r.dx())
		w.max.x = w.min.x + r.dx();
	if(w.dy() > r.dy())
		w.max.y = w.min.y + r.dy();
	size := w.size();
	if (w.max.x > r.max.x)
		(w.min.x, w.max.x) = (r.min.x - size.x, r.max.x - size.x);
	if (w.max.y > r.max.y)
		(w.min.y, w.max.y) = (r.min.y - size.y, r.max.y - size.y);
	if (w.min.x < r.min.x)
		(w.min.x, w.max.x) = (r.min.x, r.min.x + size.x);
	if (w.min.y < r.min.y)
		(w.min.y, w.max.y) = (r.min.y, r.min.y + size.y);
	return w;
}

lastrect: Rect;
# find an suitable area for a window
newrect(w, r: Rect): Rect
{
	rl: list of Rect;
	for(z := wmsrv->top(); z != nil; z = z.znext)
		for(wl := z.wins; wl != nil; wl = tl wl)
			rl = (hd wl).r :: rl;
	lastrect = winplace->place(rl, r, lastrect, w.size());
	return lastrect;
}

bufferproc(in, out: chan of string)
{
	h, t: list of string;
	dummyout := chan of string;
	for(;;){
		outc := dummyout;
		s: string;
		if(h != nil || t != nil){
			outc = out;
			if(h == nil)
				for(; t != nil; t = tl t)
					h = hd t :: h;
			s = hd h;
		}
		alt{
		x := <-in =>
			t = x :: t;
		outc <-= s =>
			h = tl h;
		}
	}
}

command(ctxt: ref Draw->Context, args: list of string, sync: chan of string)
{
	if((sh := load Sh Sh->PATH) != nil){
		sh->run(ctxt, "{$*&}" :: args);
		sync <-= nil;
		return;
	}
	fds := list of {0, 1, 2};
	sys->pctl(sys->NEWFD, fds);

	cmd := hd args;
	file := cmd;

	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	c := load Wm file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(err != "permission denied" && err != "access permission denied" && file[0]!='/' && file[0:2]!="./"){
			c = load Wm "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil){
			sync <-= sys->sprint("%s: %s\n", cmd, err);
			exit;
		}
	}
	sync <-= nil;
	c->init(ctxt, args);
}
