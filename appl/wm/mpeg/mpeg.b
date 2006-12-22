implement WmMpeg;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Point, Rect, Display, Image: import draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;
	ctxt: ref Draw->Context;

include "dialog.m";
	dialog: Dialog;

include "selectfile.m";
	selectfile: Selectfile;

include "mpegio.m";

include "arg.m";

mio: Mpegio;
decode: Mpegd;
remap: Remap;
Mpegi: import mio;

WmMpeg: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Stopped, Playing, Stepping, Paused: con iota;
state	:= Stopped;
depth := -1;
sdepth: int;
cvt: ref Image;

pixelrec: Draw->Rect;

decoders := array[] of {
1=>	Mpegd->PATH4,
2=>	Mpegd->PATH4,
4=>	Mpegd->PATH4,
8 or 16 or 24 or 32 =>	Mpegd->PATH,
};

remappers := array[] of {
1=>	Remap->PATH1,
2=>	Remap->PATH2,
4=>	Remap->PATH4,
8 or 16 or 24 or 32 =>	Remap->PATH,
};

task_cfg := array[] of {
	"canvas .c",
	"frame .b",
	"button .b.File -text File -command {send cmd file}",
	"button .b.Stop -text Stop -command {send cmd stop}",
	"button .b.Pause -text Pause -command {send cmd pause}",
	"button .b.Step -text Step -command {send cmd step}",
	"button .b.Play -text Play -command {send cmd play}",
	"frame .f",
	"label .f.file -text {File:}",
	"label .f.name",
	"pack .f.file .f.name -side left",
	"pack .b.File .b.Stop .b.Pause .b.Step .b.Play -side left",
	"pack .f -fill x",
	"pack .b -anchor w",
	"pack .c -side bottom -fill both -expand 1",
	"pack propagate . 0",
};

init(xctxt: ref Draw->Context, argv: list of string)
{
	sys  = load Sys  Sys->PATH;
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;
	selectfile= load Selectfile Selectfile->PATH;

	ctxt = xctxt;
	tkclient->init();
	dialog->init();
	selectfile->init();

	darg, tkarg: string;
	arg := load Arg Arg->PATH;
	arg->init(argv);
	while((c := arg->opt()) != 0)
		case c {
		'x' =>
			tkarg = arg->arg();
		'd' =>
			darg = arg->arg();
		}
	args := arg->argv();
	arg = nil;
	if(darg != nil)
		depth = int darg;
	sdepth = ctxt.display.image.depth;
	if (depth < 0 || depth > sdepth)
		depth = sdepth;
	(t, menubut) := tkclient->toplevel(ctxt, tkarg, "MPEG Player", 0);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for(i:=0; i<len task_cfg; i++)
		tk->cmd(t, task_cfg[i]);

	tk->cmd(t, "bind . <Configure> {send cmd resize}");
	tk->cmd(t, "update");
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	mio = load Mpegio Mpegio->PATH;
	decode = load Mpegd decoders[depth];
	remap = load Remap remappers[depth];
	if(mio == nil || decode == nil || remap == nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Loading Interfaces",
			"Failed to load the MPEG\ninterface: "+sys->sprint("%r"),
			0, "Exit"::nil);
		return;
	}
	mio->init();

	fname := "";
	ctl := chan of string;
	state = Stopped;

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq =>
		tkclient->wmctl(t, s);
	s := <-menubut =>
		if(s == "exit"){
			state = Stopped;
			return;
		}
		tkclient->wmctl(t, s);
	press := <-cmd =>
		case press {
		"file" =>
			state = Stopped;
			patterns := list of {
				"*.mpg (MPEG movie files)",
				"* (All Files)"
			};
			fname = selectfile->filename(ctxt, t.image, "Locate MPEG files",
				patterns, nil);
			if(fname != nil) {
				tk->cmd(t, ".f.name configure -text {"+fname+"}");
				tk->cmd(t, "update");
			}
		"play" =>
			if (state != Stopped) {
				state = Playing;
				continue;
			}
			if(fname != nil) {
				state = Playing;
				spawn play(t, fname);
			}
		"step" =>
			if (state != Stopped) {
				state = Stepping;
				continue;
			}
			if(fname != nil) {
				state = Stepping;
				spawn play(t, fname);
			}
		"pause" =>
			if(state == Playing)
				state = Paused;
		"stop" =>
			state = Stopped;
		}
	}
}

play(t: ref Toplevel, file: string)
{
	sp := list of { "Stop Play" };

	fd := sys->open(file, Sys->OREAD);
	if(fd == nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Open MPEG file", sys->sprint("%r"), 0, sp);
		return;
	}
	m := mio->prepare(fd, file);
	m.streaminit(Mpegio->VIDEO_STR0);
	p := m.getpicture(1);
	decode->init(m);
	remap->init(m);

	canvr := canvsize(t);
	o := Point(0, 0);
	dx := canvr.dx();
	if(dx > m.width)
		o.x = (dx - m.width)/2;
	dy := canvr.dy();
	if(dy > m.height)
		o.y = (dy - m.height)/2;
	canvr.min = canvr.min.add(o);
	canvr.max = canvr.min.add(Point(m.width, m.height));

	if (depth != sdepth){
		chans := Draw->CMAP8;
		case depth {
		0 =>	chans = Draw->GREY1;
		1 =>	chans = Draw->GREY2;
		2 =>	chans = Draw->GREY4;
		3 =>	chans = Draw->CMAP8;
		4 =>	chans = Draw->RGB16;
		5 =>	chans = Draw->RGB24;	# ?
		}
		cvt = ctxt.display.newimage(Rect((0, 0), (m.width, m.height)), chans, 0, 0);
	}

	f, pf: ref Mpegio->YCbCr;
	for(;;) {
		if(state == Stopped)
			break;
		case p.ptype {
		Mpegio->IPIC =>
			f = decode->Idecode(p);
		Mpegio->PPIC =>
			f = decode->Pdecode(p);
		Mpegio->BPIC =>
			f = decode->Bdecode(p);
		}
		while(state == Paused)
			sys->sleep(0);
		if (p.ptype == Mpegio->BPIC) {
			writepixels(t, canvr, remap->remap(f));
			if(state == Stepping)
				state = Paused;
		} else {
			if (pf != nil) {
				writepixels(t, canvr, remap->remap(pf));
				if(state == Stepping)
					state = Paused;
			}
			pf = f;
		}
		if ((p = m.getpicture(1)) == nil) {
			writepixels(t, canvr, remap->remap(pf));
			break;
		}
	}
	state = Stopped;
}

writepixels(t: ref Toplevel, r: Rect, b: array of byte)
{
	if (cvt != nil) {
		cvt.writepixels(cvt.r, b);
		t.image.draw(r, cvt, nil, (0, 0));
	} else
		t.image.writepixels(r, b);
}

canvsize(t: ref Toplevel): Rect
{
	r: Rect;

	r.min.x = int tk->cmd(t, ".c cget -actx");
	r.min.y = int tk->cmd(t, ".c cget -acty");
	r.max.x = r.min.x + int tk->cmd(t, ".c cget -width");
	r.max.y = r.min.y + int tk->cmd(t, ".c cget -height");

	return r;
}
