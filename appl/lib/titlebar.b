implement Titlebar;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "titlebar.m";

title_cfg := array[] of {
	"frame .Wm_t -bg #aaaaaa -borderwidth 1",
	"label .Wm_t.title -anchor w -bg #aaaaaa -fg white",
	"button .Wm_t.e -bitmap exit.bit -command {send wm_title exit} -takefocus 0",
	"pack .Wm_t.e -side right",
	"bind .Wm_t <Button-1> {send wm_title move %X %Y}",
	"bind .Wm_t <Double-Button-1> {send wm_title lower .}",
	"bind .Wm_t <Motion-Button-1> {}",
	"bind .Wm_t <Motion> {}",
	"bind .Wm_t.title <Button-1> {send wm_title move %X %Y}",
	"bind .Wm_t.title <Double-Button-1> {send wm_title lower .}",
	"bind .Wm_t.title <Motion-Button-1> {}",
	"bind .Wm_t.title <Motion> {}",
	"bind . <FocusIn> {.Wm_t configure -bg blue;"+
		".Wm_t.title configure -bg blue;update}",
	"bind . <FocusOut> {.Wm_t configure -bg #aaaaaa;"+
		".Wm_t.title configure -bg #aaaaaa;update}",
};

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
}

new(top: ref Tk->Toplevel, buts: int): chan of string
{
	ctl := chan of string;
	tk->namechan(top, ctl, "wm_title");

	if(buts & Plain)
		return ctl;

	for(i := 0; i < len title_cfg; i++)
		cmd(top, title_cfg[i]);

	if(buts & OK)
		cmd(top, "button .Wm_t.ok -bitmap ok.bit"+
			" -command {send wm_title ok} -takefocus 0; pack .Wm_t.ok -side right");

	if(buts & Hide)
		cmd(top, "button .Wm_t.top -bitmap task.bit"+
			" -command {send wm_title task} -takefocus 0; pack .Wm_t.top -side right");

	if(buts & Resize)
		cmd(top, "button .Wm_t.m -bitmap maxf.bit"+
			" -command {send wm_title size} -takefocus 0; pack .Wm_t.m -side right");

	if(buts & Help)
		cmd(top, "button .Wm_t.h -bitmap help.bit"+
			" -command {send wm_title help} -takefocus 0; pack .Wm_t.h -side right");

	# pack the title last so it gets clipped first
	cmd(top, "pack .Wm_t.title -side left");
	cmd(top, "pack .Wm_t -fill x");

	return ctl;
}

title(top: ref Tk->Toplevel): string
{
	if(tk->cmd(top, "winfo class .Wm_t.title")[0] != '!')
		return cmd(top, ".Wm_t.title cget -text");
	return nil;
}
	
settitle(top: ref Tk->Toplevel, t: string): string
{
	s := title(top);
	tk->cmd(top, ".Wm_t.title configure -text '" + t);
	return s;
}

sendctl(top: ref Tk->Toplevel, c: string)
{
	cmd(top, "send wm_title " + c);
}

minsize(top: ref Tk->Toplevel): Point
{
	buts := array[] of {"e", "ok", "top", "m", "h"};
	r := tk->rect(top, ".", Tk->Border);
	r.min.x = r.max.x;
	r.max.y = r.min.y;
	for(i := 0; i < len  buts; i++){
		br := tk->rect(top, ".Wm_t." + buts[i], Tk->Border);
		if(br.dx() > 0)
			r = r.combine(br);
	}
	r.max.x += tk->rect(top, ".Wm_t." + buts[0], Tk->Border).dx();
	return r.size();
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "wmclient: tk error %s on '%s'\n", e, s);
	return e;
}
