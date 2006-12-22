implement WmMpeg;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Rect, Display, Image: import draw;
	ctxt: ref Draw->Context;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;

include	"mpeg.m";
	mpeg: Mpeg;

WmMpeg: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Stopped, Playing: con iota;

dx, dy: int;
dw, dh: int;
adjust: int;

task_cfg := array[] of {
	"canvas .c -background =5",
	"frame .b",
	"button .b.File -text File -command {send cmd file}",
	"button .b.Stop -text Stop -command {send cmd stop}",
	"button .b.Pause -text Pause -command {send cmd pause}",
	"button .b.Play -text Play -command {send cmd play}",
	"button .b.Picture -text Picture -command {send cmd pict}",
	"frame .f",
	"label .f.file -text {File:}",
	"label .f.name",
	"pack .f.file .f.name -side left",
	"pack .b.File .b.Stop .b.Pause .b.Play .b.Picture -side left",
	"pack .f -fill x",
	"pack .b -anchor w",
	"pack .c -side bottom -fill both -expand 1",
	"pack propagate . 0",
};

init(xctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys  Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	mpeg = load Mpeg  Mpeg->PATH;

	ctxt = xctxt;

	tkclient->init();

	(t, menubut)  := tkclient->toplevel(ctxt.screen, "", "Mpeg Player", Tkclient->Appl);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	tkclient->tkcmds(t, task_cfg);

	tk->cmd(t, "bind . <Configure> {send cmd resize}");
	tk->cmd(t, "update");

	fname := "";
	ctl := chan of string;
	state := Stopped;

	for(;;) alt {
	menu := <-menubut =>
		if(menu == "exit") {
			if(state == Playing) {
				mpeg->ctl("stop");
				<-ctl;
			}
			return;
		}
		tkclient->wmctl(t, menu);
	press := <-cmd =>
		case press {
		"file" =>
			pat := list of {
				"*.mpg (MPEG movie file)"
			};
			fname = tkclient->filename(ctxt.screen, t, "Locate MPEG clip", pat, "");
			if(fname != nil) {
				tk->cmd(t, ".f.name configure -text {"+fname+"}");
				tk->cmd(t, "update");
			}
		"play" =>
			s := mpeg->play(ctxt.display, nil, 0, canvsize(t), fname, ctl);
			if(s != nil) {
				tkclient->dialog(t, "error -fg red", "Play MPEG",
					"Media player error:\n"+s,
					0, "Stop Play"::nil);
				break;
			}
			state = Playing;
		"resize" =>
			if(state != Playing)
				break;
			r := canvsize(t);
			s := sys->sprint("window %d %d %d %d",
					r.min.x, r.min.y, r.max.x, r.max.y);
			mpeg->ctl(s);
		"pict" =>
			if(adjust)
				break;
			adjust = 1;
			spawn pict(t);
		* =>
			# Stop & Pause
			mpeg->ctl(press);
		}
	done := <-ctl =>
		state = Stopped;
	}
}

canvsize(t: ref Toplevel): Rect
{
	r: Rect;

	r.min.x = int tk->cmd(t, ".c cget -actx") + dx;
	r.min.y = int tk->cmd(t, ".c cget -acty") + dy;
	r.max.x = r.min.x + int tk->cmd(t, ".c cget -width") + dw;
	r.max.y = r.min.y + int tk->cmd(t, ".c cget -height") + dh;

	return r;
}

pict_cfg := array[] of {
	"scale .dx -orient horizontal -from -5 -to 5 -label {Origin X}"+
		" -command { send c dx}",
	"scale .dy -orient horizontal -from -5 -to 5 -label {Origin Y}"+
		" -command { send c dy}",
	"scale .dw -orient horizontal -from -5 -to 5 -label {Width}"+
		" -command {send c dw}",
	"scale .dh -orient horizontal -from -5 -to 5 -label {Height}"+
		" -command {send c dh}",
	"pack .Wm_t -fill x",
	"pack .dx .dy .dw .dh -fill x",
	"pack propagate . 0",
	"update",
};

pict(parent: ref Toplevel)
{
	targ := +" -borderwidth 2 -relief raised";

	(t, menubut) := tkclient->toplevel(ctxt.screen, tkclient->geom(parent), "Mpeg Picture", 0);

	pchan := chan of string;
	tk->namechan(t, pchan, "c");

	tkclient->tkcmds(t, pict_cfg);

	for(;;) alt {
	menu := <-menubut =>
		if(menu == "exit") {
			adjust = 0;
			return;
		}
		tkclient->wmctl(t, menu);
	tcip := <-pchan =>
		case tcip {
		"dx" =>	dx = int tk->cmd(t, ".dx get");
		"dy" => dy = int tk->cmd(t, ".dy get");
		"dw" => dw = int tk->cmd(t, ".dw get");
		"dh" => dh = int tk->cmd(t, ".dh get");
		}
		r := canvsize(parent);
		s := sys->sprint("window %d %d %d %d",
				r.min.x, r.min.y, r.max.x, r.max.y);
		mpeg->ctl(s);
	}
}
