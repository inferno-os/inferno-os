implement Whiteboard;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Screen, Display, Image, Rect, Point, Font: import draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

Whiteboard: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

ERASEWIDTH: con 6;


stderr: ref Sys->FD;
srvfd: ref Sys->FD;
disp: ref Display;
font: ref Draw->Font;
drawctxt: ref Draw->Context;

tksetup := array[] of {
	"frame .f -bd 2",
	"frame .c -bg white -width 234 -height 279",
	"menu .penmenu",
	".penmenu add command -command {send cmd pen 0} -bitmap @/icons/whiteboard/0.bit",
	".penmenu add command -command {send cmd pen 1} -bitmap @/icons/whiteboard/1.bit",
	".penmenu add command -command {send cmd pen 2} -bitmap @/icons/whiteboard/2.bit",
	".penmenu add command -command {send cmd pen erase} -bitmap @/icons/whiteboard/erase.bit",
	"menubutton .pen -menu .penmenu -bitmap @/icons/whiteboard/1.bit",
	"button .colour -bg black -activebackground black -command {send cmd getcolour}",
	"pack .c -in .f",
	"pack .f -side top -anchor center",
	"pack .pen -side left",
	"pack .colour -side left -fill both -expand 1",
	"update",
};

tkconnected := array[] of {
	"bind .c <Button-1> {send cmd down %x %y}",
	"bind .c <ButtonRelease-1> {send cmd up %x %y}",
	"update",
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmod(Tkclient->PATH);

	if (len args < 2) {
		sys->fprint(stderr, "Usage: whiteboard [servicedir] id\n");
		raise "fail:init";
	}

	args = tl args;
	servicedir := "/n/remote/services";
	if(len args == 2)
		(servicedir, args) = (hd args, tl args);
	wbid := hd args;

	disp = ctxt.display;
	if (disp == nil) {
		sys->fprint(stderr, "bad Draw->Context\n");
		raise "fail:init";
	}
	drawctxt = ctxt;

	tkclient->init();
	(win, winctl) := tkclient->toplevel(ctxt, nil, "Whiteboard", 0);
	font = Font.open(disp, tkcmd(win, ". cget -font"));
	if(font == nil)
		font = Font.open(disp, "*default*");
	cmd := chan of string;
	tk->namechan(win, cmd, "cmd");
	tkcmds(win, tksetup);
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd" :: "ptr" :: nil);
	cimage := makeimage(win);

	sc := chan of array of (Point, Point);
	cc := chan of (string, ref Image, ref Sys->FD, ref Sys->FD);
	connected := 0;
	sfd: ref Sys->FD;
	ctlfd: ref Sys->FD;	# must keep this open to keep service active

	showtext(cimage, "connecting...");
	spawn connect(servicedir, wbid, cc);

	err: string;
	strokeimg: ref Image;
Connect:
	for (;;) alt {
	(err, strokeimg, sfd, ctlfd) = <-cc =>
		if (err == nil)
			break Connect;
		else
			showtext(cimage, "Error: " + err);

	s := <-winctl or
	s = <-win.wreq or
	s = <-win.ctxt.ctl =>
		oldimg := win.image;
		err = tkclient->wmctl(win, s);
		if(s[0] == '!' && err == nil && win.image != oldimg){
			cimage = makeimage(win);
			showtext(cimage, "connecting...");
		}
	p := <-win.ctxt.ptr =>
		tk->pointer(win, *p);
	c := <-win.ctxt.kbd =>
		tk->keyboard(win, c);
	}

	tkcmd(win, ".c configure -width " + string strokeimg.r.dx());
	tkcmd(win, ".c configure -height " + string strokeimg.r.dy());
	tkcmds(win, tkconnected);
	tkcmd(win, "update");
	cimage.draw(cimage.r, strokeimg, nil, strokeimg.r.min);

	strokesin := chan of (int, int, array of Point);
	strokesout := chan of (int, int, Point, Point);
	spawn reader(sfd, strokesin);
	spawn writer(sfd, strokesout);

	pendown := 0;
	p0, p1: Point;

	getcolour := 0;
	white := disp.white;
	whitepen := disp.newimage(Rect(Point(0,0), Point(1,1)), Draw->CMAP8, 1, Draw->White);
	pencolour := Draw->Black;
	penwidth := 1;
	erase := 0;
	drawpen := disp.newimage(Rect(Point(0,0), Point(1,1)), Draw->CMAP8, 1, pencolour);

	for (;;) alt {
	s := <-winctl or
	s = <-win.ctxt.ctl or
	s = <-win.wreq =>
		oldimg := win.image;
		err = tkclient->wmctl(win, s);
		if(s[0] == '!' && err == nil && win.image != oldimg){
			cimage = makeimage(win);
			cimage.draw(cimage.r, strokeimg, nil, strokeimg.r.min);
		}
	p := <-win.ctxt.ptr =>
		tk->pointer(win, *p);
	c := <-win.ctxt.kbd =>
		tk->keyboard(win, c);
	(colour, width, strokes) := <-strokesin =>
		if (strokes == nil)
			tkclient->settitle(win, "Whiteboard (Disconnected)");
		else {
			pen := disp.newimage(Rect(Point(0,0), Point(1,1)), Draw->CMAP8, 1, colour);
			drawstrokes(cimage, cimage.r.min, pen, width, strokes);
			drawstrokes(strokeimg, strokeimg.r.min, pen, width, strokes);
		}

	c := <-cmd =>
		(nil, toks) := sys->tokenize(c, " ");
		case hd toks {
		"down" =>
			toks = tl toks;
			x := int hd toks;
			y := int hd tl toks;
			if (!pendown) {
				pendown = 1;
				p0 = Point(x, y);
				continue;
			}
			p1 = Point(x, y);
			if (p1.x == p0.x && p1.y == p0.y)
				continue;
			pen := drawpen;
			colour := pencolour;
			width := penwidth;
			if (erase) {
				pen = whitepen;
				colour = Draw->White;
				width = ERASEWIDTH;
			}
			drawstroke(cimage, cimage.r.min, p0, p1, pen, width);
			drawstroke(strokeimg, strokeimg.r.min, p0, p1, pen, width);
			strokesout <-= (colour, width, p0, p1);
			p0 = p1;
		"up" =>
			pendown = 0;

		"getcolour" =>
			pendown = 0;
			if (!getcolour)
				spawn colourmenu(cmd);
		"colour" =>
			pendown = 0;
			getcolour = 0;
			toks = tl toks;
			if (toks == nil)
				# colourmenu was dismissed
				continue;
			erase = 0;
			tkcmd(win, ".pen configure -bitmap @/icons/whiteboard/" + string penwidth + ".bit");
			tkcmd(win, "update");
			pencolour = int hd toks;
			toks = tl toks;
			tkcolour := hd toks;
			drawpen = disp.newimage(Rect(Point(0,0), Point(1,1)), Draw->CMAP8, 1, pencolour);
			tkcmd(win, ".colour configure -bg " + tkcolour + " -activebackground " + tkcolour);
			tkcmd(win, "update");

		"pen" =>
			pendown = 0;
			p := hd tl toks;
			i := "";
			if (p == "erase") {
				erase = 1;
				i = "erase.bit";
			} else {
				erase = 0;
				penwidth = int p;
				i = p + ".bit";
			}
			tkcmd(win, ".pen configure -bitmap @/icons/whiteboard/" + i);
			tkcmd(win, "update");
		}

	}
}

makeimage(win: ref Tk->Toplevel): ref Draw->Image
{
	if(win.image == nil)
		return nil;
	scr := Screen.allocate(win.image, win.image.display.white, 0);
	w := scr.newwindow(tk->rect(win, ".c", Tk->Local), Draw->Refnone, Draw->Nofill);
	return w;
}

showtext(img: ref Image, s: string)
{
	r := img.r;
	r.max.y = img.r.min.y + font.height;
	img.draw(r, disp.white, nil, (0, 0));
	img.text(r.min, disp.black, (0, 0), font, s);
}

penmenu(t: ref Tk->Toplevel, p: Point)
{
	topy := int tkcmd(t, ".penmenu yposition 0");
	boty := int tkcmd(t, ".penmenu yposition end");
	dy := boty - topy;
	p.y -= dy;
	tkcmd(t, ".penmenu post " + string p.x + " " + string p.y);
}

colourcmds := array[] of {
	"label .l -height 10",
	"frame .c -height 224 -width 224",
	"pack .l -fill x -expand 1",
	"pack .c -side bottom -fill both -expand 1",
	"pack propagate . 0",
	"bind .c <Button-1> {send cmd push %x %y}",
	"bind .c <ButtonRelease-1> {send cmd release}",
};

lastcolour := "255";
lasttkcolour := "#000000";

colourmenu(c: chan of string)
{
	(t, winctl) := tkclient->toplevel(drawctxt, nil, "Whiteboard", Tkclient->OK);
	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	tkcmds(t, colourcmds);
	tkcmd(t, ".l configure -bg " + lasttkcolour);
	tkcmd(t, "update");
	tkclient->onscreen(t, "onscreen");
	tkclient->startinput(t, "kbd" :: "ptr" :: nil);

	drawcolours(t.image, tk->rect(t, ".c", Tk->Local));

	for(;;) alt {
	p := <-t.ctxt.ptr =>
		tk->pointer(t, *p);
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-winctl or
	s = <-t.ctxt.ctl or
	s = <-t.wreq =>
		case s{
		"ok" =>
			c <-= "colour " + lastcolour + " " + lasttkcolour;
			return;
		"exit" =>
			c <-= "colour";
			return;
		* =>
			oldimage := t.image;
			e := tkclient->wmctl(t, s);
			if(s[0] == '!' && e == nil && oldimage != t.image)
				drawcolours(t.image, tk->rect(t, ".c", Tk->Local));
		}

	press := <-cmd =>
		(n, word) := sys->tokenize(press, " ");
		case hd word {
		"push" =>
			(lastcolour, lasttkcolour) = color(int hd tl word, int hd tl tl word, tk->rect(t, ".c", 0).size());
			tkcmd(t, ".l configure -bg " + lasttkcolour);
		}
	}
}

drawcolours(img: ref Image, cr: Rect)
{
	# use writepixels because it's much faster than allocating all those colors.
	tmp := disp.newimage(((0,0),(cr.dx(),cr.dy()/16+1)), Draw->CMAP8, 0, 0);
	if(tmp == nil)
		return;
	buf := array[tmp.r.dx()*tmp.r.dy()] of byte;
	dx := cr.dx();
	dy := cr.dy();
	for(y:=0; y<16; y++){
		for(i:=tmp.r.dx()-1; i>=0; --i)
			buf[i] = byte (16*y+(16*i)/dx);
		for(k:=tmp.r.dy()-1; k>=1; --k)
			buf[dx*k:] = buf[0:dx];
		tmp.writepixels(tmp.r, buf);
		r: Rect;
		r.min.x = cr.min.x;
		r.max.x = cr.max.x;
		r.min.y = cr.min.y+(dy*y)/16;
		r.max.y = cr.min.y+(dy*(y+1))/16;
		img.draw(r, tmp, nil, tmp.r.min);
	}
}

color(x, y: int, size: Point): (string, string)
{
	x = (16*x)/size.x;
	y = (16*y)/size.y;
	col := 16*y+x;
	(r, g, b) := disp.cmap2rgb(col);
	tks := sys->sprint("#%.2x%.2x%.2x", r, g, b);
	return (string disp.cmap2rgba(col), tks);
}

opensvc(dir: string, svc: string, name: string): (ref Sys->FD, string, string)
{
	ctlfd := sys->open(dir+"/ctl", Sys->ORDWR);
	if(ctlfd == nil)
		return (nil, nil, sys->sprint("can't open %s/ctl: %r", dir));
	if(sys->fprint(ctlfd, "%s %s", svc, name) <= 0)
		return (nil, nil, sys->sprint("can't access %s service %s: %r", svc, name));
	buf := array [32] of byte;
	sys->seek(ctlfd, big 0, Sys->SEEKSTART);
	n := sys->read(ctlfd, buf, len buf);
	if (n <= 0)
		return (nil, nil, sys->sprint("%s/ctl: protocol error: %r", dir));
	return (ctlfd, dir+"/"+string buf[0:n], nil);
}

connect(dir, name: string, res: chan of (string, ref Image, ref Sys->FD, ref Sys->FD))
{
	(ctlfd, srvdir, emsg) := opensvc(dir, "whiteboard", name);
	if(ctlfd == nil) {
		res <-= (emsg, nil, nil, nil);
		return;
	}

	bitpath := srvdir + "/wb.bit";
	strokepath := srvdir + "/strokes";

	sfd := sys->open(strokepath, Sys->ORDWR);
	if (sfd == nil) {
		err := sys->sprint("cannot open whiteboard data: %r");
		res <-= (err, nil, nil, nil);
		srvfd = nil;
		return;
	}

	bfd := sys->open(bitpath, Sys->OREAD);
	if (bfd == nil) {
		err := sys->sprint("cannot open whiteboard image: %r");
		res <-= (err, nil, nil, nil);
		srvfd = nil;
		return;
	}

	img := disp.readimage(bfd);
	if (img == nil) {
		err := sys->sprint("cannot read whiteboard image: %r");
		res <-= (err, nil, nil, nil);
		srvfd = nil;
		return;
	}
sys->print("read image ok\n");

	# make sure image is depth 8 (because of image.line() bug)
	if (img.depth != 8) {
sys->print("depth is %d, not 8\n", img.depth);
		nimg := disp.newimage(img.r, Draw->CMAP8, 0, 0);
		if (nimg == nil) {
			res <-= ("cannot allocate local image", nil, nil, nil);
			srvfd = nil;
			return;
		}
		nimg.draw(nimg.r, img, nil, img.r.min);
		img = nimg;
	}

	res <-= (nil, img, sfd, ctlfd);
}

reader(fd: ref Sys->FD, sc: chan of (int, int, array of Point))
{
	buf := array [Sys->ATOMICIO] of byte;

	for (;;) {
		n := sys->read(fd, buf, len buf);
		if (n <= 0) {
			sc <-= (0, 0, nil);
			return;
		}
		s := string buf[0:n];
		(npts, toks) := sys->tokenize(s, " ");
		if (npts & 1)
			# something wrong
			npts--;
		if (npts < 6)
			# ignore
			continue;

		colour, width: int;
		(colour, toks) = (int hd toks, tl toks);
		(width, toks) = (int hd toks, tl toks);
		pts := array [(npts - 2)/ 2] of Point;
		for (i := 0; toks != nil; i++) {
			x, y: int;
			(x, toks) = (int hd toks, tl toks);
			(y, toks) = (int hd toks, tl toks);
			pts[i] = Point(x, y);
		}
		sc <-= (colour, width, pts);
		pts = nil;
	}
}

Wmsg: adt {
	data: array of byte;
	datalen: int;
	next: cyclic ref Wmsg;
};

writer(fd: ref Sys->FD, sc: chan of (int, int, Point, Point))
{
	lastcol := -1;
	lastw := -1;
	lastpt := Point(-1, -1);
	curmsg: ref Wmsg;
	nextmsg: ref Wmsg;

	eofc := chan of int;
	wc := chan of ref Wmsg;
	wseof := 0;
	spawn wslave(fd, wc, eofc);

	for (;;) {
		colour := -1;
		width := 0;
		p0, p1: Point;

		if (curmsg == nil || wseof)
			(colour, width, p0, p1) = <-sc;
		else alt {
		wseof = <-eofc =>
			;

		(colour, width, p0, p1) = <-sc =>
			;

		wc <-= curmsg =>
			curmsg = curmsg.next;
			continue;
		}

		newseq := 0;
		if (curmsg == nil) {
			curmsg = ref Wmsg(array [Sys->ATOMICIO] of byte, 0, nil);
			nextmsg = curmsg;
			newseq = 1;
		}

		if (colour != lastcol || width != lastw || p0.x != lastpt.x || p0.y != lastpt.y)
			newseq = 1;

		d: array of byte = nil;
		if (!newseq) {
			d = sys->aprint(" %d %d", p1.x, p1.y);
			if (nextmsg.datalen + len d >= Sys->ATOMICIO) {
				nextmsg.next = ref Wmsg(array [Sys->ATOMICIO] of byte, 0, nil);
				nextmsg = nextmsg.next;
				newseq = 1;
			}
		}
		if (newseq) {
			d = sys->aprint(" %d %d %d %d %d %d", colour, width, p0.x, p0.y, p1.x, p1.y);
			if (nextmsg.datalen != 0) {
				nextmsg.next = ref Wmsg(array [Sys->ATOMICIO] of byte, 0, nil);
				nextmsg = nextmsg.next;
			}
		}
		nextmsg.data[nextmsg.datalen:] = d;
		nextmsg.datalen += len d;
		lastcol = colour;
		lastw = width;
		lastpt = p1;
	}
}

wslave(fd: ref Sys->FD, wc: chan of ref Wmsg, eof: chan of int)
{
	for (;;) {
		wm := <-wc;
		n := sys->write(fd, wm.data, wm.datalen);
		if (n != wm.datalen)
			break;
	}
	eof <-= 1;
}

drawstroke(img: ref Image, offset, p0, p1: Point, pen: ref Image, width: int)
{
	p0 = p0.add(offset);
	p1 = p1.add(offset);
	img.line(p0, p1, Draw->Endsquare, Draw->Endsquare, width, pen, p0);
}

drawstrokes(img: ref Image, offset: Point, pen: ref Image, width: int, pts: array of Point)
{
	if (len pts < 2)
		return;
	p0, p1: Point;
	p0 = pts[0].add(offset);
	for (i := 1; i < len pts; i++) {
		p1 = pts[i].add(offset);
		img.line(p0, p1, Draw->Endsquare, Draw->Endsquare, width, pen, p0);
		p0 = p1;
	}
}

badmod(mod: string)
{
	sys->fprint(stderr, "cannot load %s: %r\n", mod);
	raise "fail:bad module";
}

tkcmd(t: ref Tk->Toplevel, cmd: string): string
{
	s := tk->cmd(t, cmd);
	if (s != nil && s[0] == '!') {
		sys->fprint(stderr, "%s\n", cmd);
		sys->fprint(stderr, "tk error: %s\n", s);
	}
	return s;
}

tkcmds(t: ref Tk->Toplevel, cmds: array of string)
{
	for (i := 0; i < len cmds; i++)
		tkcmd(t, cmds[i]);
}
