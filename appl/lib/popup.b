implement Popup;
include "sys.m";
	sys: Sys;
include "draw.m";
	Point: import Draw;
include "tk.m";
	tk: Tk;
include "popup.m";

init()
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
}

post(win: ref Tk->Toplevel, p: Point, a: array of string, n: int): chan of int
{
	rc := chan of int;
	spawn postproc(win, p, a, n, rc);
	return rc;
}

postproc(win: ref Tk->Toplevel, p: Point, a: array of string, n: int, rc: chan of int)
{
	c := chan of string;
	tk->namechan(win, c, "c.popup");
	mkpopupmenu(win, a);
	cmd(win, ".popup entryconfigure " + string n + " -state active");
	cmd(win, "bind .popup <Unmap> {send c.popup unmap}");

	dy := ypos(win, n) - ypos(win, 0);
	p.y -= dy;
	cmd(win, ".popup post " + string p.x + " " + string p.y +
		";grab set .popup");
	n = -1;
	while ((e := <-c) != "unmap")
		n = int e;

	cmd(win, "destroy .popup");
	rc <-= n;
}

mkpopupmenu(win: ref Tk->Toplevel, a: array of string)
{
	cmd(win, "menu .popup");
	for (i := 0; i < len a; i++) {
		cmd(win, ".popup add command -command {send c.popup " + string i +
			"} -text '" + a[i]);
	}
}

Blank: con "-----";

# XXX what should we do about popups containing no items.
mkbutton(win: ref Tk->Toplevel, w: string, a: array of string, n: int): chan of string
{
	c := chan of string;
	if (len a == 0) {
		cmd(win, "label " + w + " -bd 2 -relief raised -text '" + Blank);
		return c;
	}
	tk->namechan(win, c, "c" + w);
	mkpopupmenu(win, a);
	cmd(win, "label " + w + " -bd 2 -relief raised -width [.popup cget -width] -text '" + a[n]);
	cmd(win, "bind " + w + " <Button-1> {send c" + w + " " + w + "}");
	cmd(win, "destroy .popup");
	return c;
}

changebutton(win: ref Tk->Toplevel, w: string, a: array of string, n: int)
{
	if (len a > 0) {
		mkpopupmenu(win, a);
		cmd(win, w + " configure -width [.popup cget -width] -text '" + a[n]);
		cmd(win, "bind " + w + " <Button-1> {send c" + w + " " + w + "}");
		cmd(win, "destroy .popup");
	} else {
		cmd(win, w + " configure -text '" + Blank);
		cmd(win, "bind " + w + " <Button-1> {}");
	}
}

add(a: array of string, s: string): (array of string, int)
{
	for (i := 0; i < len a; i++)
		if (s == a[i])
			return (a, i);
	na := array[len a + 1] of string;
	na[0:] = a;
	na[len a] = s;
	return (na, len a);
}

#event(win: ref Tk->Toplevel, e: string, a: array of string): int
#{
#	w := e;
#	p := Point(int cmd(win, w + " cget -actx"), int cmd(win, w + " cget -acty"));
#	s := cmd(win, w + " cget -text");
#	for (i := 0; i < len a; i++)
#		if (s == a[i])
#			break;
#	if (i == len a)
#		i = 0;
#		
#	n := post(win, p, a, i);
#	if (n != -1) {
#		cmd(win, w + " configure -text '" + a[n]);
#		i = n;
#	}
#	return i;
#}

ypos(win: ref Tk->Toplevel, n: int): int
{
	return int cmd(win, ".popup yposition " + string n);
}

cmd(win: ref Tk->Toplevel, s: string): string
{
	r := tk->cmd(win, s);
	if (len r > 0 && r[0] == '!')
		sys->print("error executing '%s': %s\n", s, r[1:]);
	return r;
}
