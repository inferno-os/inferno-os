implement Graph;

include "common.m";

sys : Sys;
drawm : Draw;
dat : Dat;
gui : Gui;
utils : Utils;

Image, Point, Rect, Font, Display : import drawm;
black, white, display : import gui;
error : import utils;

refp : ref Point;
pixarr : array of byte;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	drawm = mods.draw;
	dat = mods.dat;
	gui = mods.gui;
	utils = mods.utils;

	refp = ref Point;
	refp.x = refp.y = 0;
}

charwidth(f : ref Font, c : int) : int
{
	s : string = "z";

	s[0] = c;
	return f.width(s);
}

strwidth(f : ref Font, s : string) : int
{
	return f.width(s);
}

balloc(r : Rect, c : Draw->Chans, col : int) : ref Image
{
	im := display.newimage(r, c, 0, col);
	if (im == nil)
		error("failed to get new image");
	return im;
}

draw(d : ref Image, r : Rect, s : ref Image, m : ref Image, p : Point)
{
	d.draw(r, s, m, p);
}

stringx(d : ref Image, p : Point, f : ref Font, s : string, c : ref Image)
{
	d.text(p, c, (0, 0), f, s);
}

cursorset(p : Point)
{
	gui->cursorset(p);
}

cursorswitch(c : ref Dat->Cursor)
{
	gui->cursorswitch(c);
}

binit()
{
}

bflush()
{
}

berror(s : string)
{
	error(s);
}
