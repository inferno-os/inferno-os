implement Colors;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Point, Rect, Image: import draw;
include "tk.m";
	tk: Tk;
include	"tkclient.m";
	tkclient: Tkclient;

Colors: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

display: ref Display;
top: ref Tk->Toplevel;
tmpi: ref Image;

task_cfg := array[] of {
	"panel .c",
	"label .l -anchor w -text {col:}",
	"pack .l -fill x",
	"pack .c -fill both -expand 1",
	"bind .c <Button-1> {grab set .c; send cmd %X %Y}",
	"bind .c <ButtonRelease-1> {grab release .c}",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	spawn init1(ctxt);
}

init1(ctxt: ref Draw->Context)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	tkclient->init();
	display = ctxt.display;
	tmpi = display.newimage(((0,0), (1, 1)), Draw->RGB24, 0, 0);

	titlectl: chan of string;
	(top, titlectl) = tkclient->toplevel(ctxt, "", "Colors", Tkclient->Appl);

	cmdch := chan of string;
	tk->namechan(top, cmdch, "cmd");

	for (i := 0; i < len task_cfg; i++)
		cmd(top, task_cfg[i]);
	tk->putimage(top, ".c", cmap((256, 256)), nil);
	cmd(top, "pack propagate . 0");
	cmd(top, "update");
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);

	for(;;) alt {
	s := <-top.ctxt.kbd =>
		tk->keyboard(top, s);
	s := <-top.ctxt.ptr =>
		tk->pointer(top, *s);
	c := <-top.ctxt.ctl or
	c = <-top.wreq or
	c = <-titlectl =>
		if(c == "exit")
			return;
		e := tkclient->wmctl(top, c);
		if(e == nil && c[0] == '!'){
			tk->putimage(top, ".c", cmap(actr(".c").size()), nil);
			cmd(top, "update");
		}

	press := <-cmdch =>
		(nil, toks) := sys->tokenize(press, " ");
		color((int hd toks, int hd tl toks));
	}
}

color(p: Point)
{
	r, g, b: int;
	col: string;

	cr := actr(".c");
	if(p.in(cr)){
		p = p.sub(cr.min);
		p.x = (16*p.x)/cr.dx();
		p.y = (16*p.y)/cr.dy();
		(r, g, b) = display.cmap2rgb(16*p.y+p.x);
		col = string (16*p.y+p.x);
	}else{
		tmpi.draw(tmpi.r, display.image, nil, p);
		data := array[3] of byte;
		ok := tmpi.readpixels(tmpi.r, data);
		if(ok != len data)
			return;
		(r, g, b) = (int data[2], int data[1], int data[0]);
		c := display.rgb2cmap(r, g, b);
		(r1, g1, b1) := display.cmap2rgb(c);
		if (r == r1 && g == g1 && b == b1)
			col = string c;
		else
			col = "~" + string c;
	}

	cmd(top, ".l configure -text " +
		sys->sprint("{col:%s #%.6X r%d g%d b%d}", col, (r<<16)|(g<<8)|b, r, g, b));
	cmd(top, "update");
}

cmap(size: Point): ref Image
{
	# use writepixels because it's much faster than allocating all those colors.
	img := display.newimage(((0, 0), size), Draw->CMAP8, 0, 0);
	if (img == nil){
		sys->print("colors: cannot make new image: %r\n");
		return nil;
	}

	dy := (size.y / 16 + 1);
	buf := array[size.x * dy] of byte;

	for(y:=0; y<16; y++){
		for (i := 0; i < size.x; i++)
			buf[i] = byte (16*y + (16*i)/size.x);
		for (i = 1; i < dy; i++)
			buf[size.x*i:] = buf[0:size.x];
		img.writepixels(((0, (y*size.y)/16), (size.x, ((y+1)*size.y) / 16)), buf);
	}
	return img;
}

actr(w: string): Rect
{
	r: Rect;
	bd := int cmd(top, w + " cget -bd");
	r.min.x = int cmd(top, w + " cget -actx") + bd;
	r.min.y = int cmd(top, w + " cget -acty") + bd;
	r.max.x = r.min.x + int cmd(top, w + " cget -actwidth");
	r.max.y = r.min.y + int cmd(top, w + " cget -actheight");
	return r;
}

cmd(top: ref Tk->Toplevel, cmd: string): string
{
	e := tk->cmd(top, cmd);
	if (e != nil && e[0] == '!')
		sys->print("colors: tk error on '%s': %s\n", cmd, e);
	return e;
}
