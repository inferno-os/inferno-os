implement WmQt;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;
	ctxt: ref Draw->Context;

include "quicktime.m";
	qt: QuickTime;

WmQt: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Stopped, Playing: con iota;

task_cfg := array[] of {
	"canvas .c",
	"frame .b",
	"button .b.File -text File -command {send cmd file}",
	"button .b.Stop -text Stop -command {send cmd stop}",
	"button .b.Pause -text Pause -command {send cmd pause}",
	"button .b.Play -text Play -command {send cmd play}",
	"frame .f",
	"label .f.file -text {File:}",
	"label .f.name",
	"pack .f.file .f.name -side left",
	"pack .b.File .b.Stop .b.Pause .b.Play -side left",
	"pack .f -fill x",
	"pack .b -anchor w",
	"pack .c -side bottom -fill both -expand 1",
	"pack propagate . 0",
};

init(xctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "qt: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;

	ctxt = xctxt;

	tkclient->init();
	(t, menubut) := tkclient->toplevel(ctxt.screen, "", "QuickTime Player", 0);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	tkclient->tkcmds(t, task_cfg);

	tk->cmd(t, "bind . <Configure> {send cmd resize}");
	tk->cmd(t, "update");

	qt = load QuickTime QuickTime->PATH;
	if(qt == nil) {
		tkclient->dialog(t, "error -fg red", "Load Module",
				"Failed to load the QuickTime interface:\n"+
					sys->sprint("%r"),
				0, "Exit"::nil);
		return;
	}
	qt->init();

	fname := "";
	ctl := chan of string;
	state := Stopped;

	for(;;) alt {
	menu := <-menubut =>
		if(menu == "exit")
			return;
		tkclient->wmctl(t, menu);
	press := <-cmd =>
		case press {
		"file" =>
			pat := list of {
				"*.mov (Apple QuickTime Movie)"
			};
			fname = tkclient->filename(ctxt.screen, t, "Locate Movie", pat, "");
			if(fname != nil) {
				s := fname;
				if(len s > 25)
					s = "..."+fname[len s - 25:];
				tk->cmd(t, ".f.name configure -text {"+s+"}");
				tk->cmd(t, "update");
			}
		"play" =>
			if(fname != nil)
				spawn play(t, fname);
		}
	}
}

#
# Parse the atoms describing a movie
#
moov(t: ref Toplevel, q: ref QuickTime->QD)
{
	for(;;) {
		(h, l) := qt->q.atomhdr();
		if(l < 0)
			break;
		case h {
		* =>
			qt->q.skipatom(l);
		"mvhd" =>
			err := qt->q.mvhd(l);
			if(err == nil)
				break;
			tkclient->dialog(t, "error -fg red", "Parse Headers",
					err,
					0, "Exit"::nil);
			exit;
		"trak" =>
			err := qt->q.trak(l);
			if(err == nil)
				break;
			tkclient->dialog(t, "error -fg red", "Parse Track",
					err,
					0, "Exit"::nil);
			exit;
		}
	}
}

play(t: ref Toplevel, file: string)
{
	(q, err) := qt->open(file);
	if(err != nil) {
		tkclient->dialog(t, "error -fg red", "Open Movie",
					"Failed to open \""+file+"\"\n"+err,
					0, "Continue"::nil);
		return;
	}
	for(;;) {
		(h, l) := qt->q.atomhdr();
		if(l < 0)
			break;
		case h {
		* =>
			qt->q.skipatom(l);
		"moov" =>
			moov(t, q);
		}
	}
}
