implement Textwidget;

#
# textwidget.b — Text display primitives for Draw-based apps
#
# See module/textwidget.m for interface documentation.
#

include "sys.m";

include "draw.m";
	draw: Draw;
	Font, Image, Point, Rect: import draw;

include "textwidget.m";

init()
{
	draw = load Draw Draw->PATH;
}

# ── Tabulator ────────────────────────────────────────────────

Tabulator.new(tabstop: int): ref Tabulator
{
	if(tabstop <= 0)
		tabstop = 8;
	return ref Tabulator(tabstop);
}

Tabulator.expand(tab: self ref Tabulator, s: string): string
{
	result := "";
	col := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\t') {
			spaces := tab.tabstop - (col % tab.tabstop);
			for(j := 0; j < spaces; j++) {
				result[len result] = ' ';
				col++;
			}
		} else {
			result[len result] = s[i];
			col++;
		}
	}
	return result;
}

Tabulator.unexpandcol(tab: self ref Tabulator, s: string, expcol: int): int
{
	col := 0;
	ecol := 0;
	for(i := 0; i < len s && ecol < expcol; i++) {
		if(s[i] == '\t') {
			spaces := tab.tabstop - (col % tab.tabstop);
			ecol += spaces;
			col += spaces;
		} else {
			ecol++;
			col++;
		}
		if(ecol >= expcol)
			return i + 1;
	}
	return len s;
}

Tabulator.expandedcol(tab: self ref Tabulator, s: string, col: int): int
{
	ecol := 0;
	for(i := 0; i < col && i < len s; i++) {
		if(s[i] == '\t')
			ecol += tab.tabstop - (ecol % tab.tabstop);
		else
			ecol++;
	}
	return ecol;
}

# ── Word wrapping ────────────────────────────────────────────

wrapend(font: ref Font, s: string, start, maxpx: int): int
{
	if(start >= len s)
		return len s;
	w := 0;
	k := start;
	while(k < len s) {
		cw := font.width(s[k:k+1]);
		if(w + cw > maxpx)
			break;
		w += cw;
		k++;
	}
	if(k == start)
		k++;		# guarantee at least one char
	return k;
}

# ── Selection drawing ────────────────────────────────────────

drawselection(dst: ref Image, font: ref Font,
	      selcolor: ref Image,
	      expanded: string, cs, ce: int,
	      selstart_ex, selend_ex: int,
	      textx, y, lineheight: int)
{
	# Clip selection to this chunk
	cselstart := selstart_ex;
	if(cselstart < cs)
		cselstart = cs;
	cselend := selend_ex;
	if(cselend > ce)
		cselend = ce;
	if(cselstart >= cselend)
		return;

	startx := textx + font.width(expanded[cs:cselstart]);
	endx   := textx + font.width(expanded[cs:cselend]);
	selr := Rect((startx, y), (endx, y + lineheight));
	dst.draw(selr, selcolor, nil, Point(0, 0));
}
