implement MDisplay;

#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#
# - best viewed with acme!

include "sys.m";
include "draw.m";
include "mdisplay.m";

sys		: Sys;
draw		: Draw;

Context, Point, Rect, Font, Image, Display, Screen : import draw;


# len cell		== number of lines
# len cell[0]	== number of cellmap cells per char
# (x,y)*cellsize	== font glyph clipr

cellS		:= array [] of {array [] of {(0, 0)}};
cellW	:= array [] of {array [] of {(0, 0), (1, 0)}};
cellH		:= array [] of {array [] of {(0, 1)}, array [] of {(0, 0)}};
cellWH	:= array [] of {array [] of {(0, 1), (1, 1)}, array [] of {(0, 0), (1, 0)}};

Cellinfo : adt {
	font		: ref Font;
	ch, attr	: int;
	clipmod	: (int, int);
};


# current display attributes
display	: ref Display;
window	: ref Image;
frames	:= array [2] of ref Image;
update	: chan of int;

colours	: array of ref Image;
bright	: ref Image;

# current mode attributes
cellmap	: array of Cellinfo;
nrows	: int;
ncols	: int;
ulheight	: int;
curpos	: Point;
winoff	: Point;
cellsize	: Point;
modeattr	: con fgWhite | bgBlack;
showC	:= 0;
delims	:= 0;
modbbox := Rect((0,0),(0,0));
blankrow	: array of Cellinfo;

ctxt		: ref Context;
font		: ref Font;	# g0 videotex font - extended with unicode g2 syms
fonth	: ref Font;	# double height version of font
fontw	: ref Font;	# double width
fonts		: ref Font;	# double size
fontg1	: ref Font;	# semigraphic videotex font (ch+128=separated)
fontfr	: ref Font;	# french character set
fontusa	: ref Font;	# american character set


Init(c : ref Context) : string
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;

	if (c == nil || c.display == nil)
		return "no display context";

	ctxt = c;
	disp := ctxt.display;

	black	:= disp.rgb2cmap(0, 0, 0);
	blue		:= disp.rgb2cmap(0, 0, 255);
	red		:= disp.rgb2cmap(255, 0, 0);
	magenta	:= disp.rgb2cmap(255, 0, 255);
	green	:= disp.rgb2cmap(0, 255, 0);
	cyan		:= disp.rgb2cmap(0, 255, 255);
	yellow	:= disp.rgb2cmap(255, 255, 0);
	white	:= disp.rgb2cmap(240, 240, 240);

	iblack	:= disp.color(black);
	iblue		:= disp.color(blue);
	ired		:= disp.color(red);
	imagenta	:= disp.color(magenta);
	igreen	:= disp.color(green);
	icyan	:= disp.color(cyan);
	iyellow	:= disp.color(yellow);
	iwhite	:= disp.color(white);

	colours	= array [] of {	iblack, iblue, ired, imagenta,
						igreen, icyan, iyellow, iwhite};
	bright	= disp.color(disp.rgb2cmap(255, 255, 255));
	
	update = chan of int;
	spawn Update(update);
	display = disp;
	return nil;
}

Quit()
{
	if (update != nil)
		update <- = QuitUpdate;
	update	= nil;
	window	= nil;
	frames[0]	= nil;
	frames[1]	= nil;
	cellmap	= nil;
	display	= nil;
}

Mode(r : Draw->Rect, w, h, ulh, d : int, fontpath : string) : (string, ref Draw->Image)
{
	if (display == nil)
		# module not properly Init()'d
		return ("not initialized", nil);

	curpos = Point(-1, -1);
	if (window != nil)
		update <- = Pause;

	cellmap = nil;
	window = nil;
	(dx, dy) := (r.dx(), r.dy());
	if (dx == 0 || dy == 0) {
		return (nil, nil);
	}

	black := display.rgb2cmap(0, 0, 0);
	window = ctxt.screen.newwindow(r, Draw->Refbackup, black);
	if (window == nil)
		return ("cannot create window", nil);

	window.origin(Point(0,0), r.min);
	winr := Rect((0,0), (dx, dy));
	frames[0] = display.newimage(winr, window.chans, 0, black);
	frames[1] = display.newimage(winr, window.chans, 0, black);

	if (window == nil || frames[0] == nil || frames[1] == nil) {
		window = nil;
		return ("cannot allocate display resources", nil);
	}

	ncols = w;
	nrows = h;
	ulheight = ulh;
	delims = d;
	showC = 0;

	cellmap = array [ncols * nrows] of Cellinfo;
	
	font		= Font.open(display, fontpath);
	fontw	= Font.open(display, fontpath + "w");
	fonth	= Font.open(display, fontpath + "h");
	fonts		= Font.open(display, fontpath + "s");
	fontg1	= Font.open(display, fontpath + "g1");
	fontfr	= Font.open(display, fontpath + "fr");
	fontusa	= Font.open(display, fontpath + "usa");

	if (font != nil)
		cellsize = Point(font.width(" "), font.height);
	else
		cellsize = Point(dx/ncols, dy / nrows);

	winoff.x = (dx - (cellsize.x * ncols)) / 2;
	winoff.y = (dy - (cellsize.y * nrows)) /2;
	if (winoff.x < 0)
		winoff.x = 0;
	if (winoff.y < 0)
		winoff.y = 0;

	blankrow = array [ncols] of {* => Cellinfo(font, ' ', modeattr | fgWhite, (0,0))};
	for (y := 0; y < nrows; y++) {
		col0 := y * ncols;
		cellmap[col0:] = blankrow;
	}

#	frames[0].clipr = frames[0].r;
#	frames[1].clipr = frames[1].r;
#	frames[0].draw(frames[0].r, colours[0], nil, Point(0,0));
#	frames[1].draw(frames[1].r, colours[0], nil, Point(0,0));
#	window.draw(window.r, colours[0], nil, Point(0,0));
	update <- = Continue;
	return (nil, window);
}

Cursor(pt : Point)
{
	if (update == nil || cellmap == nil)
		# update thread (cursor/character flashing) not running
		return;

	# normalize pt
	pt.x--;

	curpos = pt;
	update <- = CursorSet;
}

Put(str : string, pt : Point, charset, attr, insert : int)
{
	if (cellmap == nil || str == nil)
		# nothing to do
		return;

	# normalize pt
	pt.x--;

	f : ref Font;
	cell := cellS;

	case charset {
	videotex		=>
		if (!(attr & attrD))
			attr &= (fgMask | attrF | attrH | attrW | attrP);
		if (attr & attrW && attr & attrH) {
			cell = cellWH;
			f = fonts;
		} else if (attr & attrH) {
			cell = cellH;
			f = fonth;
		} else if (attr & attrW) {
			cell = cellW;
			f = fontw;
		} else {
			f = font;
		}

	semigraphic	=>
		f = fontg1;
		if (attr & attrL) {
			# convert to "separated"
			newstr := "";
			for (ix := 0; ix < len str; ix++)
				newstr[ix] = str[ix] + 16r80;
			str = newstr;
		}
		# semigraphic charset does not support size / polarity attributes
		# attrD always set later once field attr established
		attr &= ~(attrD | attrH | attrW | attrP | attrL);

	french		=>	f = fontfr;
	american		=>	f = fontusa;
	*			=>	f = font;
	}

	update <- = Pause;

	txty := pt.y - (len cell - 1);
	for (cellix := len cell - 1; cellix >= 0; cellix--) {
		y := pt.y - cellix;

		if (y < 0)
			continue;
		if (y >= nrows)
			break;

		col0 := y * ncols;
		colbase := pt.y * ncols;

		if (delims && !(attr & attrD)) {
			# seek back for a delimiter
			mask : int;
			delimattr := modeattr;

			# semigraphics only inherit attrC from current field
			if (charset == semigraphic)
				mask = attrC;
			else
				mask  = bgMask | attrC | attrL;

			for (ix := pt.x-1; ix >= 0; ix--) {
				cix := ix + col0;
				if (cellmap[cix].attr & attrD) {
					if (cellmap[cix].font == fontg1 && f != fontg1)
						# don't carry over attrL from semigraphic field
						mask &= ~attrL;

					delimattr = cellmap[cix].attr;
					break;
				}
			}
			attr = (attr & ~mask) | (delimattr & mask);

			# semigraphics validate background colour
			if (charset == semigraphic)
				attr |= attrD;
		}

		strlen := len cell[0] * len str;
		gfxwidth := cellsize.x * strlen;
		srco := Point(pt.x*cellsize.x, y*cellsize.y);

		if (insert) {
			# copy existing cells and display to new position
			if (pt.x + strlen < ncols) {
				for (destx := ncols -1; destx > pt.x; destx--) {
					srcx := destx - strlen;
					if (srcx < 0)
						break;
					cellmap[col0 + destx] = cellmap[col0 + srcx];
				}

				# let draw() do the clipping for us
				dsto := Point(srco.x + gfxwidth, srco.y);
				dstr := Rect((dsto.x, srco.y), (ncols * cellsize.x, srco.y + cellsize.y));
				
				frames[0].clipr = frames[0].r;
				frames[1].clipr = frames[1].r;
				frames[0].draw(dstr, frames[0], nil, srco);
				frames[1].draw(dstr, frames[1], nil, srco);
				if (modbbox.dx() == 0)
					modbbox = dstr;
				else
					modbbox = boundingrect(modbbox, dstr);
			}
		}

		# copy-in new string
		x := pt.x;
		for (strix := 0; x < ncols && strix < len str; strix++) {
			for (clipix := 0; clipix < len cell[cellix]; (x, clipix) = (x+1, clipix+1)) {
				if (x < 0)
					continue;
				if (x >= ncols)
					break;
				cmix := col0 + x;
				cellmap[cmix].font = f;
				cellmap[cmix].ch = str[strix];
				cellmap[cmix].attr = attr;
				cellmap[cmix].clipmod = cell[cellix][clipix];
			}
		}

		# render the new string
		txto := Point(srco.x, txty * cellsize.y);
		strr := Rect(srco, (srco.x + gfxwidth, srco.y + cellsize.y));
		if (strr.max.x > ncols * cellsize.x)
			strr.max.x = ncols * cellsize.x;

		drawstr(str, f, strr, txto, attr);

		# redraw remainder of line until find cell not needing redraw

		# this could be optimised by
		# spotting strings with same attrs, font and clipmod pairs
		# and write out whole string rather than processing
		# a char at a time

		attr2 := attr;
		mask := bgMask | attrC | attrL;
		s := "";
		for (; delims && x < ncols; x++) {
			if (x < 0)
				continue;
			newattr := cellmap[col0 + x].attr;

			if (cellmap[col0 + x].font == fontg1) {
				# semigraphics act as bg colour delimiter
				attr2 = (attr2 & ~bgMask) | (newattr & bgMask);
				mask &= ~attrL;
			} else
				if (newattr & attrD)
					break;

			if ((attr2 & mask) == (newattr & mask))
				break;
			newattr = (newattr & ~mask) | (attr2 & mask);
			cellmap[col0 + x].attr = newattr;
			s[0] = cellmap[col0 + x].ch;
			(cx, cy) := cellmap[col0 + x].clipmod;
			f2 := cellmap[col0 + x].font;

			cellpos := Point(x * cellsize.x, y * cellsize.y);
			clipr := Rect(cellpos, cellpos.add(Point(cellsize.x, cellsize.y)));
			drawpt := cellpos.sub(Point(cx*cellsize.x, cy*cellsize.y));
			drawstr(s, f2, clipr, drawpt, newattr);
		}
	}
	update <- = Continue;
}

Scroll(topline, nlines : int)
{
	if (cellmap == nil || nlines == 0)
		return;

	blankr : Rect;
	scr := Rect((0,topline * cellsize.y), (ncols * cellsize.x, nrows * cellsize.y));

	update <- = Pause;

	frames[0].clipr = scr;
	frames[1].clipr = scr;
	dstr := scr.subpt(Point(0, nlines * cellsize.y));

	frames[0].draw(dstr, frames[0], nil, frames[0].clipr.min);
	frames[1].draw(dstr, frames[1], nil, frames[1].clipr.min);

	if (nlines > 0) {
		# scroll up - copy up from top
		if (nlines > nrows - topline)
			nlines = nrows - topline;
		for (y := nlines + topline; y < nrows; y++) {
			srccol0 := y * ncols;
			dstcol0 := (y - nlines) * ncols;
			cellmap[dstcol0:] = cellmap[srccol0:srccol0+ncols];
		}
		for (y = nrows - nlines; y < nrows; y++) {
			col0 := y * ncols;
			cellmap[col0:] = blankrow;
		}
		blankr = Rect(Point(0, scr.max.y - (nlines * cellsize.y)), scr.max);
	} else {
		# scroll down - copy down from bottom
		nlines = -nlines;
		if (nlines > nrows - topline)
			nlines = nrows - topline;
		for (y := (nrows - 1) - nlines; y >= topline; y--) {
			srccol0 := y * ncols;
			dstcol0 := (y + nlines) * ncols;
			cellmap[dstcol0:] = cellmap[srccol0:srccol0+ncols];
		}
		for (y = topline; y < nlines; y++) {
			col0 := y * ncols;
			cellmap[col0:] = blankrow;
		}
		blankr = Rect(scr.min, (scr.max.x, scr.min.y + (nlines * cellsize.y)));
	}
	frames[0].draw(blankr, colours[0], nil, Point(0,0));
	frames[1].draw(blankr, colours[0], nil, Point(0,0));
	if (modbbox.dx()  == 0)
		modbbox = scr;
	else
		modbbox = boundingrect(modbbox, scr);
	update <- = Continue;
}

Reveal(show : int)
{
	showC = show;
	if (cellmap == nil)
		return;

	update <- = Pause;
	for (y := 0; y < nrows; y++) {
		col0 := y * ncols;
		for (x := 0; x < ncols; x++) {
			attr := cellmap[col0+x].attr;
			if (!(attr & attrC))
				continue;

			s := "";
			s[0] = cellmap[col0 + x].ch;
			(cx, cy) := cellmap[col0 + x].clipmod;
			f := cellmap[col0 + x].font;
			cellpos := Point(x * cellsize.x, y * cellsize.y);
			clipr := Rect(cellpos, cellpos.add(Point(cellsize.x, cellsize.y)));
			drawpt := cellpos.sub(Point(cx*cellsize.x, cy*cellsize.y));

			drawstr(s, f, clipr, drawpt, attr);
		}
	}
	update <- = Continue;
}

# expects that pt.x already normalized
wordchar(pt : Point) : int
{
	if (pt.x < 0 || pt.x >= ncols)
		return 0;
	if (pt.y < 0 || pt.y >= nrows)
		return 0;

	col0 := pt.y * ncols;
	c := cellmap[col0 + pt.x];

	if (c.attr & attrC && !showC)
		# don't let clicking on screen 'reveal' concealed chars!
		return 0;

	if (c.font == fontg1)
		return 0;

	if (c.attr & attrW) {
		# check for both parts of character
		(modx, nil) := c.clipmod;
		if (modx == 1) {
			# rhs of char - check lhs is the same
			if (pt.x <= 0)
				return 0;
			lhc := cellmap[col0 + pt.x-1];
			(lhmodx, nil) := lhc.clipmod;
			if (!((lhc.attr & attrW) && (lhc.font == c.font) && (lhc.ch == c.ch) && (lhmodx == 0)))
				return 0;
		} else {
			# lhs of char - check rhs is the same
			if (pt.x >= ncols - 1)
				return 0;
			rhc := cellmap[col0 + pt.x + 1];
			(rhmodx, nil) := rhc.clipmod;
			if (!((rhc.attr & attrW) && (rhc.font == c.font) && (rhc.ch == c.ch) && (rhmodx == 1)))
				return 0;
		}
	}
	if (c.ch >= 16r30 && c.ch <= 16r39)
		# digits
		return 1;
	if (c.ch >= 16r41 && c.ch <= 16r5a)
		# capitals
		return 1;
	if (c.ch >= 16r61 && c.ch <= 16r7a)
		# lowercase
		return 1;
	if (c.ch == '*' || c.ch == '/')
		return 1;
	return 0;
}

GetWord(gfxpt : Point) : string
{
	if (cellmap == nil)
		return nil;

	scr := Rect((0,0), (ncols * cellsize.x, nrows * cellsize.y));
	gfxpt = gfxpt.sub(winoff);

	if (!gfxpt.in(scr))
		return nil;

	x := gfxpt.x / cellsize.x;
	y := gfxpt.y / cellsize.y;
	col0 := y * ncols;

	s := "";

	# seek back
	for (sx := x; sx >= 0; sx--)
		if (!wordchar(Point(sx, y)))
			break;

	if (sx++ == x)
		return nil;

	# seek forward, constructing s
	for (; sx < ncols; sx++) {
		if (!wordchar(Point(sx, y)))
			break;
		c := cellmap[col0 + sx];
		s[len s] = c.ch;
		if (c.attr & attrW)
			sx++;
	}
	return s;
}

Refresh()
{
	if (window == nil || modbbox.dx() == 0)
		return;

	if (update != nil)
		update <- = Redraw;
}

framecolours(attr : int) : (ref Image, ref Image, ref Image, ref Image)
{
	fg : ref Image;
	fgcol := attr & fgMask;
	if (fgcol == fgWhite && attr & attrB)
		fg = bright;
	else
		fg = colours[fgcol / fgBase];

	bg : ref Image;
	bgcol := attr & bgMask;
	if (bgcol == bgWhite && attr & attrB)
		bg = bright;
	else
		bg = colours[bgcol / bgBase];

	(fg0, fg1) := (fg, fg);
	(bg0, bg1) := (bg, bg);

	if (attr & attrP)
		(fg0, bg0, fg1, bg1) = (bg1, fg1, bg0, fg0);

	if (attr & attrF) {
		fg0 = fg;
		fg1 = bg;
	}

	if ((attr & attrC) && !showC)
		(fg0, fg1) = (bg0, bg1);
	return (fg0, bg0, fg1, bg1);
}

kill(pid : int)
{
	prog := "/prog/" + string pid + "/ctl";
	fd := sys->open(prog, Sys->OWRITE);
	if (fd != nil) {
		cmd := array of byte "kill";
		sys->write(fd, cmd, len cmd);
	}
}

timer(ms : int, pc, tick : chan of int)
{
	pc <- = sys->pctl(0, nil);
	for (;;) {
		sys->sleep(ms);
		tick <- = 1;
	}
}

# Update() commands
Redraw, Pause, Continue, CursorSet, QuitUpdate : con iota;

Update(cmd : chan of int)
{
	flashtick := chan of int;
	cursortick := chan of int;
	pc := chan of int;
	spawn timer(1000, pc, flashtick);
	flashpid := <- pc;
	spawn timer(500, pc, cursortick);
	cursorpid := <- pc;

	cursor	: Point;
	showcursor := 0;
	cursoron	:= 0;
	quit		:= 0;
	nultick	:= chan of int;
	flashchan	:= nultick;
	pcount	:= 1;
	fgframe	:= 0;

	for (;!quit ;) alt {
	c := <- cmd =>
		case c {
		Redraw =>
			frames[0].clipr = frames[0].r;
			frames[1].clipr = frames[1].r;
			r := modbbox.addpt(winoff);
			window.draw(r.addpt(window.r.min), frames[fgframe], nil, modbbox.min);
			if (showcursor && cursoron)
				drawcursor(cursor, fgframe, 1);
			modbbox = Rect((0,0),(0,0));

		Pause =>
			if (pcount++ == 0)
				flashchan = nultick;

		Continue =>
			pcount--;
			if (pcount == 0)
				flashchan = flashtick;

		QuitUpdate =>
			quit++;

		CursorSet =>
			frames[0].clipr = frames[0].r;
			frames[1].clipr = frames[1].r;
			if (showcursor && cursoron)
				drawcursor(cursor, fgframe, 0);
			cursoron = 0;
			if (curpos.x < 0 || curpos.x >= ncols || curpos.y < 0  || curpos.y >= nrows)
				showcursor = 0;
			else {
				cursor = curpos;
				showcursor = 1;
				drawcursor(cursor, fgframe, 1);
				cursoron = 1;
			}
		}

	<- flashchan =>
		# flip displays...
		fgframe = (fgframe + 1 ) % 2;
		modbbox = Rect((0,0),(0,0));
		frames[0].clipr = frames[0].r;
		frames[1].clipr = frames[1].r;
		window.draw(window.r.addpt(winoff), frames[fgframe], nil, Point(0,0));
		if (showcursor && cursoron)
			drawcursor(cursor, fgframe, 1);

	<- cursortick =>
		if (showcursor) {
			cursoron = !cursoron;
			drawcursor(cursor, fgframe, cursoron);
		}
	}
	kill(flashpid);
	kill(cursorpid);
}


drawstr(s : string, f : ref Font, clipr : Rect, drawpt : Point, attr : int)
{
	(fg0, bg0, fg1, bg1) := framecolours(attr);
	frames[0].clipr = clipr;
	frames[1].clipr = clipr;
	frames[0].draw(clipr, bg0, nil, Point(0,0));
	frames[1].draw(clipr, bg1, nil, Point(0,0));
	ulrect : Rect;
	ul := (attr & attrL) && ! (attr & attrD);

	if (f != nil) {
		if (ul)
			ulrect = Rect((drawpt.x, drawpt.y + f.height - ulheight), (drawpt.x + clipr.dx(), drawpt.y + f.height));
		if (fg0 != bg0) {
			frames[0].text(drawpt, fg0, Point(0,0), f, s);
			if (ul)
				frames[0].draw(ulrect, fg0, nil, Point(0,0));
		}
		if (fg1 != bg1) {
			frames[1].text(drawpt, fg1, Point(0,0), f, s);
			if (ul)
				frames[1].draw(ulrect, fg1, nil, Point(0,0));
		}
	}
	if (modbbox.dx() == 0)
		modbbox = clipr;
	else
		modbbox = boundingrect(modbbox, clipr);
}

boundingrect(r1, r2 : Rect) : Rect
{
	if (r2.min.x < r1.min.x)
		r1.min.x = r2.min.x;
	if (r2.min.y < r1.min.y)
		r1.min.y = r2.min.y;
	if (r2.max.x > r1.max.x)
		r1.max.x = r2.max.x;
	if (r2.max.y > r1.max.y)
		r1.max.y = r2.max.y;
	return r1;
}

drawcursor(pt : Point, srcix, show : int)
{
	col0 := pt.y * ncols;
	c := cellmap[col0 + pt.x];
	s := "";

	s[0] = c.ch;
	(cx, cy) := c.clipmod;
	cellpos := Point(pt.x * cellsize.x, pt.y * cellsize.y);
	clipr := Rect(cellpos, cellpos.add(Point(cellsize.x, cellsize.y)));
	clipr = clipr.addpt(winoff);
	clipr = clipr.addpt(window.r.min);

	drawpt := cellpos.sub(Point(cx*cellsize.x, cy*cellsize.y));
	drawpt = drawpt.add(winoff);
	drawpt = drawpt.add(window.r.min);

	if (!show) {
		# copy from appropriate frame buffer
		window.draw(clipr, frames[srcix], nil, cellpos);
		return;
	}

	# invert colours
	attr := c.attr ^ (fgMask | bgMask);

	fg, bg : ref Image;
	f := c.font;
	if (srcix == 0)
		(fg, bg, nil, nil) = framecolours(attr);
	else
		(nil, nil, fg, bg) = framecolours(attr);

	prevclipr := window.clipr;
	window.clipr = clipr;

	window.draw(clipr, bg, nil, Point(0,0));
	ulrect : Rect;
	ul := (attr & attrL) && ! (attr & attrD);

	if (f != nil) {
		if (ul)
			ulrect = Rect((drawpt.x, drawpt.y + f.height - ulheight), (drawpt.x + clipr.dx(), drawpt.y + f.height));
		if (fg != bg) {
			window.text(drawpt, fg, Point(0,0), f, s);
			if (ul)
				window.draw(ulrect, fg, nil, Point(0,0));
		}
	}
	window.clipr = prevclipr;
}
