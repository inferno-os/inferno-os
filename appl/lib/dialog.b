implement Dialog;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Screen, Rect, Point: import draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";

init(): string
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();
	return nil;
}

STEP: con 20;

#
# find upper left corner for subsidiary child window (always at constant
# position relative to parent)
#
localgeom(im: ref Draw->Image): string
{
	if (im == nil)
		return nil;

	return sys->sprint("-x %d -y %d", im.r.min.x+STEP, im.r.min.y+STEP);
}

centre(t: ref Toplevel)
{
	org: Point;
	org.x = t.image.screen.image.r.dx() / 2 - t.image.r.dx() / 2;
	org.y = t.image.screen.image.r.dy() / 3 - t.image.r.dy() / 2;
	if (org.y < 0)
		org.y = 0;
	cmd(t, ". configure -x " + string org.x + " -y " + string org.y);
}

tkcmds(top: ref Tk->Toplevel, a: array of string)
{
	n := len a;
	for(i := 0; i < n; i++)
		tk->cmd(top, a[i]);
}

dialog_config := array[] of {
	"label .top.ico",
	"label .top.msg",
	"frame .top -relief raised -bd 1",
	"frame .bot -relief raised -bd 1",
	"pack .top.ico -side left -padx 10 -pady 10",
	"pack .top.msg -side left -expand 1 -fill both -padx 10 -pady 10",
	"pack .Wm_t .top .bot -side top -fill both",
	"focus ."
};

prompt(ctxt: ref Draw->Context,
	parent: ref Draw->Image,
	ico: string,
	title:string,
	msg: string,
	dflt: int,
	labs : list of string): int
{
	where := localgeom(parent);

	(t, tc) := tkclient->toplevel(ctxt, where, title, Tkclient->Popup);

	d := chan of string;
	tk->namechan(t, d, "d");

	tkcmds(t, dialog_config);
	cmd(t, ".top.msg configure -text '" + msg);
	if (ico != nil)
		cmd(t, ".top.ico configure -bitmap " + ico);

	n := len labs;
	for(i := 0; i < n; i++) {
		cmd(t, "button .bot.button" +
				string(i) + " -command {send d " +
				string(i) + "} -text '" + hd labs);

		if(i == dflt) {
			cmd(t, "frame .bot.default -relief sunken -bd 1");
			cmd(t, "pack .bot.default -side left -expand 1 -padx 10 -pady 8");
			cmd(t, "pack .bot.button" + string i +
				" -in .bot.default -side left -padx 10 -pady 8 -ipadx 8 -ipady 4");
		}
		else
			cmd(t, "pack .bot.button" + string i +
				" -side left -expand 1 -padx 10 -pady 10 -ipadx 8 -ipady 4");
		labs = tl labs;
	}

	if(dflt >= 0)
		cmd(t, "bind . <Key-\n> {send d " + string dflt + "}");

	e := cmd(t, "variable lasterror");
	if(e != "") {
		sys->fprint(sys->fildes(2), "Dialog error: %s\n", e);
		return dflt;
	}
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd" :: "ptr" :: nil);
	cmd(t, "update");

	for(;;) alt {
	c := <-t.ctxt.kbd =>
		tk->keyboard(t, c);
	p := <-t.ctxt.ptr =>
		tk->pointer(t, *p);
	c := <-t.ctxt.ctl or
	c = <-t.wreq =>
		tkclient->wmctl(t, c);
	ans := <-d =>
		return int ans;
	tcs := <-tc =>
		if(tcs == "exit")
			return dflt;
		tkclient->wmctl(t, tcs);
	}

}

getstring_config := array[] of {
	"label .lab",
	"entry .ent -relief sunken -bd 2 -width 200",
	"pack .lab .ent -side left",
	"bind .ent <Key-\n> {send f 1}",
	"focus .ent"
};

getstring(ctxt: ref Draw->Context, parent: ref Draw->Image, msg: string): string
{
	where := localgeom(parent);
	(t, wmctl) := tkclient->toplevel(ctxt, where + " -borderwidth 2 -relief raised", nil, Tkclient->Popup);
	f := chan of string;
	tk->namechan(t, f, "f");

	tkcmds(t, getstring_config);
	cmd(t, ".lab configure -text '" + msg + ":   ");
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd" :: "ptr" :: nil);

	e := tk->cmd(t, "variable lasterror");
	if(e != "") {
		sys->print("getstring error: %s\n", e);
		return "";
	}
	cmd(t, "update");

	for(;;)alt{
	c := <-t.ctxt.kbd =>
		tk->keyboard(t, c);
	p := <-t.ctxt.ptr =>
		tk->pointer(t, *p);
	c := <-t.ctxt.ctl or
	c = <-wmctl =>
		if(c == "exit")
			return nil;
		tkclient->wmctl(t, c);
	<-f =>
		return tk->cmd(t, ".ent get");
	}
}
Showtk: con 0;

cmd(top: ref Tk->Toplevel, s: string): string
{
	if (Showtk)
		sys->print("%s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "Dialog: tk error %s on '%s'\n", e, s);
	return e;
}
