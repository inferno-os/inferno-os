implement Rioimport;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Image, Point, Rect, Display, Screen: import draw;
include "wmsrv.m";
	wmsrv: Wmsrv;
include "sh.m";
	sh: Sh;
include "string.m";
	str: String;

Rioimport: module{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Client: adt{
	ptrstarted:	int;
	kbdstarted:	int;
	state:		int;		# Hidden|Current
	req:		chan of (array of byte, Sys->Rwrite);
	resize:	chan of ref Riowin;
	ptr:		chan of ref Draw->Pointer;
	riowctl:	chan of (ref Riowin, int);
	wins:	list of ref Riowin;
	winfd:	ref Sys->FD;
	sc: 		ref Wmsrv->Client;
};

Riowin: adt {
	tag:		string;
	img:		ref Image;
	dir:		string;
	state:	int;
	ptrpid:	int;
	kbdpid:	int;
	ctlpid:	int;
	ptrfd:	ref Sys->FD;
	ctlfd:		ref Sys->FD;
};

Hidden, Current: con 1<<iota;
Ptrsize: con 1+4*12;		# 'm' plus 4 12-byte decimal integers
P9PATH: con "/n/local";
Borderwidth: con 4;		# defined in /sys/include/draw.h

display: ref Display;
wsysseq := 0;
screenr := Rect((0, 0), (640, 480));	# no way of getting this reliably from rio

Minwinsize: con Point(100, 42);

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	sh = load Sh Sh->PATH;
	sh->initialise();
	str = load String String->PATH;
	wmsrv = load Wmsrv Wmsrv->PATH;

	wc := chan of (ref Draw->Context, string);
	spawn rioproxy(wc);
	(ctxt, err) := <-wc;
	if(err != nil){
		sys->fprint(sys->fildes(2), "rioimport: %s\n", err);
		raise "fail:no display";
	}
	sh->run(ctxt, tl argv);
}

ebind(a, b: string, flag: int)
{
	if(sys->bind(a, b, flag) == -1){
		sys->fprint(sys->fildes(2), "rioimport: cannot bind %q onto %q: %r\n", a, b);
		raise "fail:error";
	}
}

rioproxy(wc: chan of (ref Draw->Context, string))
{
	{
		rioproxy1(wc);
	} exception e {
	"fail:*" =>
		wc <-= (nil, e[5:]);
	}
}

rioproxy1(wc: chan of (ref Draw->Context, string))
{
	sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: nil);

	ebind("#U*", P9PATH, Sys->MREPL);
	display = Display.allocate(P9PATH + "/dev");
	if(display == nil)
		raise sys->sprint("fail:cannot allocate display: %r");


	(wm, join, req) := wmsrv->init();
	if(wm == nil){
		wc <-= (nil, sys->sprint("%r"));
		return;
	}
	readscreenr();
	wc <-= (ref Draw->Context(display, nil, wm), nil);

	sys->pctl(Sys->FORKNS, nil);
	ebind("#₪", "/srv", Sys->MREPL|Sys->MCREATE);
	if(sys->bind(P9PATH+"/dev/draw", "/dev/draw", Sys->MREPL) == -1)
		ebind(P9PATH+"/dev", "/dev", Sys->MAFTER);
	sh->run(nil, "mount" :: "{mntgen}" :: "/mnt" :: nil);

	clients: array of ref Client;
	nc := 0;
	for(;;) alt{
	(sc, rc) := <-join =>
		if(nc != 0)
			rc <-= "only one client available";
		sync := chan of (ref Client, string);
		spawn clientproc(sc,sync);
		(c, err) := <-sync;
		rc <-= err;
		if(c != nil){
			if(sc.id >= len clients)
				clients = (array[sc.id + 1] of ref Client)[0:] = clients;
			clients[sc.id] = c;
		}
	(sc, data, rc) := <-req =>
		clients[sc.id].req <-= (data, rc);
		if(rc == nil)
			clients[sc.id] = nil;
	}
}
zclient: Client;
clientproc(sc: ref Wmsrv->Client, rc: chan of (ref Client, string))
{
	c := ref zclient;
	c.req = chan of (array of byte, Sys->Rwrite);
	c.resize = chan of ref Riowin;
	c.ptr = chan of ref Draw->Pointer;
	c.riowctl = chan of (ref Riowin, int);
	c.sc = sc;
	rc <-= (c, nil);

loop:
	for(;;) alt{
	(data, drc) := <-c.req =>
		if(drc == nil)
			break loop;
		err := handlerequest(c, data);
		n := len data;
		if(err != nil)
			n = -1;
		alt{
		drc <-= (n, err) =>;
		* =>;
		}
	p := <-c.ptr =>
		sc.ptr <-= p;
	w := <-c.resize =>
		if((c.state & Hidden) == 0)
			sc.ctl <-= sys->sprint("!reshape %q -1 0 0 0 0 getwin", w.tag);
	(w, state) := <-c.riowctl =>
		if((c.state^state)&Current)
			sc.ctl <-= "haskbdfocus " + string ((state & Current)!=0);
		if((c.state^state)&Hidden){
			s := "unhide";
			if(state&Hidden)
				s = "hide";
			for(wl := c.wins; wl != nil; wl = tl wl){
				if(hd wl != w)
					rioctl(hd wl, s);
				if(c.state&Hidden)
					sc.ctl <-= sys->sprint("!reshape %q -1 0 0 0 0 getwin", (hd wl).tag);
			}
		}
		c.state = state;
		w.state = state;
	}
	sc.stop <-= 1;
	for(wl := c.wins; wl != nil; wl = tl wl)
		delwin(hd wl);
}

handlerequest(c: ref Client, data: array of byte): string
{
	req := string data;
#sys->print("%d: %s\n", c.sc.id, req);
	if(req == nil)
		return "no request";
	args := str->unquoted(req);
	n := len args;
	case hd args {
	"key" =>
		return "permission denied";
	"ptr" =>
		# ptr x y
		if(n != 3)
			return "bad arg count";
		if(c.ptrstarted == 0)
			return "pointer not active";
		for(w := c.wins; w != nil; w = tl w){
			if((hd w).ptrfd != nil){
				sys->fprint((hd w).ptrfd, "m%11d %11d", int hd tl args, int hd tl tl args);
				return nil;
			}
		}
		return "no windows";
	"start" =>
		if(n != 2)
			return "bad arg count";
		case hd tl args {
		"ptr" or
		"mouse" =>
			if(c.ptrstarted == -1)
				return "already started";
			sync := chan of int;
			for(w := c.wins; w != nil; w = tl w){
				spawn ptrproc(hd w, c.ptr, c.resize, sync);
				(hd w).ptrpid = <-sync;
			}
			c.ptrstarted = 1;
			return nil;
		"kbd" =>
			if(c.kbdstarted == -1)
				return "already started";
			sync := chan of int;
			for(w := c.wins; w != nil; w = tl w){
				spawn kbdproc(hd w, c.sc.kbd, sync);
				(hd w).kbdpid = <-sync;
			}
			return nil;
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
		if(r.dx() < Minwinsize.x)
			r.max.x = r.min.x + Minwinsize.x;
		if(r.dy() < Minwinsize.y)
			r.max.y = r.min.y + Minwinsize.y;

		spec := "";
		if(args != nil){
			case hd args{
			"onscreen" =>
				r = fitrect(r, screenr).inset(-Borderwidth);
				spec = "-r " + r2s(r);
			"place" =>
				r = fitrect(r, screenr).inset(-Borderwidth);
				spec = "-dx " + string r.dx() + " -dy " + string r.dy();
			"exact" =>
				spec = "-r " + r2s(r.inset(-Borderwidth));
			"max" =>
				r = screenr;			# XXX don't obscure toolbar?
				spec = "-r " + r2s(r.inset(Borderwidth));
			"getwin" =>
				;						# just get the new image
			* =>
				return "unkown placement method";
			}
		}else
			spec = "-r " + r2s(r.inset(-Borderwidth));
		return reshape(c, tag, spec);
	"delete" =>
		# delete tag
		if(tl args == nil)
			return "tag required";
		tag := hd tl args;
		nw: list of ref Riowin;
		for(w := c.wins; w != nil; w = tl w){
			if((hd w).tag == tag){
				delwin(hd w);
				wmsrv->c.sc.setimage(tag, nil);
			}else
				nw = hd w :: nw;
		}
		c.wins = nil;
		for(; nw != nil; nw = tl nw)
			c.wins = hd nw :: c.wins;
	"label" =>
		if(n != 2)
			return "bad arg count";
		for(w := c.wins; w != nil; w = tl w)
			setlabel(hd w, hd tl args);
	"raise" =>
		for(w := c.wins; w != nil; w = tl w){
			rioctl(hd w, "top");
			if(tl w == nil)
				rioctl(hd w, "current");
		}
	"lower" =>
		for(w := c.wins; w != nil; w = tl w)
			rioctl(hd w, "bottom");
	"task" =>
		if(n != 2)
			return "bad arg count";
		c.state |= Hidden;
		for(w := c.wins; w != nil; w = tl w){
			setlabel(hd w, hd tl args);
			rioctl(hd w, "hide");
		}
	"untask" =>
		wins: list of ref Riowin;
		for(w := c.wins; w != nil; w = tl w)
			wins = hd w :: wins;
		for(; wins != nil; wins = tl wins)
			rioctl(hd wins, "unhide");
	"!move" =>
		# !move tag reqid startx starty
		if(n != 5)
			return "bad arg count";
		args = tl args;
		tag := hd args; args = tl args;
		args = tl args;
		w := wmsrv->c.sc.window(tag);
		if(w == nil)
			return "no such tag";
		return dragwin(c.ptr, c, w, Point(int hd args, int hd tl args));
	"!size" =>
		return "nope";
	"kbdfocus" =>
		if(n != 2)
			return "bad arg count";
		if(int hd tl args){
			if(c.wins != nil)
				return rioctl(hd c.wins, "current");
		}
		return nil;
	* =>
		return "unknown request";
	}
	return nil;
}

dragwin(ptr: chan of ref Draw->Pointer, c: ref Client, w: ref Wmsrv->Window, click: Point): string
{
#	if(buttons == 0)
#		return "too late";
	p: ref Draw->Pointer;
	img := w.img.screen.image;
	r := img.r;
	off := click.sub(r.min);
	do{
		p = <-ptr;
		img.origin(r.min, p.xy.sub(off));
	} while (p.buttons != 0);
	c.sc.ptr <-= p;
#	buttons = 0;
	nr: Rect;
	nr.min = p.xy.sub(off);
	nr.max = nr.min.add(r.size());
	if(nr.eq(r))
		return "not moved";
	reshape(c, w.tag, "-r " + r2s(nr));
	return nil;
}

rioctl(w: ref Riowin, req: string): string
{
	if(sys->fprint(w.ctlfd, "%s", req) == -1){
#sys->print("rioctl fail %s: %s: %r\n", w.dir, req);
		return sys->sprint("%r");
}
#sys->print("rioctl %s: %s\n", w.dir, req);
	return nil;
}

reshape(c: ref Client, tag: string, spec: string): string
{
	for(wl := c.wins; wl != nil; wl = tl wl)
		if((hd wl).tag == tag)
			break;
	if(wl == nil){
		(w, e) := newwin(c, tag, spec);
		if(w == nil){
sys->print("can't make new win (spec %q): %s\n", spec, e);
			return e;
		}
		c.wins = w :: c.wins;
		wmsrv->c.sc.setimage(tag, w.img);
		sync := chan of int;
		if(c.kbdstarted){
			spawn kbdproc(w, c.sc.kbd, sync);
			w.kbdpid = <-sync;
		}
		if(c.ptrstarted){
			spawn ptrproc(w, c.ptr, c.resize, sync);
			w.ptrpid = <-sync;
		}
		return nil;
	}
	w := hd wl;
	if(spec != nil){
		e := rioctl(w, "resize " + spec);
		if(e != nil)
			return e;
	}
	getwin(w);
	if(w.img == nil)
		return "getwin failed";
	wmsrv->c.sc.setimage(tag, w.img);
	return nil;
}

zriowin: Riowin;
newwin(c: ref Client, tag, spec: string): (ref Riowin, string)
{
	wsys := readfile(P9PATH + "/env/wsys");
	if(wsys == nil)
		return (nil, "no $wsys");
	
	d := "/mnt/"+string wsysseq++;
	fd := sys->open(wsys, Sys->ORDWR);
	if(fd == nil)
		return (nil, sys->sprint("cannot open %q: %r\n", wsys));
	# XXX this won't multiplex properly - srv9 should export attach files (actually that's what plan 9 should do)
	if(sys->mount(fd, nil, d, Sys->MREPL, "new "+spec) == -1)
		return (nil, sys->sprint("mount %q failed: %r", wsys));
	(ok, nil) := sys->stat(d + "/winname");
	if(ok == -1)
		return (nil, "could not make window");
	w := ref zriowin;
	w.tag = tag;
	w.dir = d;
	getwin(w);
	w.ctlfd = sys->open(d + "/wctl", Sys->ORDWR);
	setlabel(w, "inferno "+string sys->pctl(0, nil)+"."+tag);
	sync := chan of int;
	spawn ctlproc(w, c.riowctl, sync);
	w.ctlpid = <-sync;
	return (w, nil);
}

setlabel(w: ref Riowin, s: string)
{
	fd := sys->open(w.dir + "/label", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "%s", s);
}

ctlproc(w: ref Riowin, wctl: chan of (ref Riowin, int), sync: chan of int)
{
	sync <-= sys->pctl(0, nil);
	buf := array[1024] of byte;
	for(;;){
		n := sys->read(w.ctlfd, buf, len buf);
		if(n <= 0)
			break;
		if(n > 4*12){
			state := 0;
			(nil, toks) := sys->tokenize(string buf[4*12:], " ");
			if(hd toks == "current")
				state |= Current;
			if(hd tl toks == "hidden")
				state |= Hidden;
			wctl <-= (w, state);
		}
	}
#sys->print("riowctl eof\n");
}

delwin(w: ref Riowin)
{
	sys->unmount(nil, w.dir);
	kill(w.ptrpid, "kill");
	kill(w.kbdpid, "kill");
	kill(w.ctlpid, "kill");
}

getwin(w: ref Riowin): int
{
	s := readfile(w.dir + "/winname");
#sys->print("getwin %s\n", s);
	i := display.namedimage(s);
	if(i == nil)
		return -1;
	scr := Screen.allocate(i, display.white, 0);
	if(scr == nil)
		return -1;
	wi := scr.newwindow(i.r.inset(Borderwidth), Draw->Refnone, Draw->Nofill);
	if(wi == nil)
		return -1;
	w.img = wi;
	return 0;
}

kbdproc(w: ref Riowin, keys: chan of int, sync: chan of int)
{
	sys->pctl(Sys->NEWFD, nil);
	cctl := sys->open(w.dir + "/consctl", Sys->OWRITE);
	sys->fprint(cctl, "rawon");
	fd := sys->open(w.dir + "/cons", Sys->OREAD);
	if(fd == nil){
		sync <-= -1;
		return;
	}
	sync <-= sys->pctl(0, nil);
	buf := array[12] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0){
		s := string buf[0:n];
		for(j := 0; j < len s; j++)
			keys <-= int s[j];
	}
#sys->print("eof on kbdproc\n");
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

ptrproc(w: ref Riowin, ptr: chan of ref Draw->Pointer, resize: chan of ref Riowin, sync: chan of int)
{
	w.ptrfd = sys->open(w.dir + "/mouse", Sys->ORDWR);
	if(w.ptrfd == nil){
		sync <-= -1;
		return;
	}
	sync <-= sys->pctl(0, nil);

	b:= array[Ptrsize] of byte;
	while((n := sys->read(w.ptrfd, b, len b)) > 0){
		if(n > 0 && int b[0] == 'r'){
#sys->print("ptrproc got resize: %s\n", string b[0:n]);
			resize <-= w;
		}else{
			p := bytes2ptr(b);
			if(p != nil)
				ptr <-= p;
		}
	}
#sys->print("eof on ptrproc\n");
}

bytes2ptr(b: array of byte): ref Draw->Pointer
{
	if(len b < Ptrsize || int b[0] != 'm')
		return nil;
	x := int string b[1:13];
	y := int string b[13:25];
	but := int string b[25:37];
	msec := int string b[37:49];
	return ref Draw->Pointer (but, (x, y), msec);
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[0:n];	
}

readscreenr()
{
	fd := sys->open(P9PATH + "/dev/screen", Sys->OREAD);
	if(fd == nil)
		return ;
	buf := array[5*12] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= len buf)
		return;
	screenr.min.x = int string buf[12:23];
	screenr.min.y = int string buf[24:35];
	screenr.max.x = int string buf[36:47];
	screenr.max.y = int string buf[48:];
}

r2s(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}

kill(pid: int, note: string): int
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}
