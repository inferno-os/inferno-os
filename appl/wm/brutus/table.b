implement Brutusext;

# <Extension table tablefile>

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Point, Font, Rect: import draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "bufio.m";

include "string.m";
	S: String;

include "html.m";
	html: HTML;
	Lex, Attr, RBRA, Data, Ttable, Tcaption, Tcol, Ttr, Ttd: import html;

include "brutus.m";
	Size6, Size8, Size10, Size12, Size16, NSIZE,
	Roman, Italic, Bold, Type, NFONT, NFONTTAG,
	Example, List, Listelem, Heading, Nofill, Author, Title,
	DefFont, DefSize, TitleFont, TitleSize, HeadingFont, HeadingSize: import Brutus;

include "brutusext.m";

Name: con "Table";

# alignment types
Anone, Aleft, Acenter, Aright, Ajustify, Atop, Amiddle, Abottom, Abaseline: con iota;

# A cell has a number of Lines, each of which has a number of Items.
# Each Item is a string in one font.
Item: adt
{
	itemid: int;	# canvas text item id
	s: string;
	fontnum: int;	# (style*NumSizes + size)
	pos: Point;	# nw corner of text item, relative to line origin
	width: int;		# of s, in pixels,  when displayed in font
	line: cyclic ref Line;   # containing line
	prev: cyclic ref Item;
	next: cyclic ref Item;
};

Line: adt
{
	items: cyclic ref Item;
	pos: Point;	# nw corner of Line relative to containing cell;
	height: int;
	ascent: int;
	width: int;
	cell: cyclic ref Tablecell;  # containing cell
	next: cyclic ref Line;
};

Align: adt
{
	halign: int;
	valign: int;
};

Tablecell: adt
{
	cellid: int;
	content: array of ref Lex;
	lines: cyclic ref Line;
	rowspan: int;
	colspan: int;
	nowrap: int;
	align: Align;
	width: int;
	height: int;
	ascent: int;
	row: int;
	col: int;
	pos: Point;	# nw corner of cell, in canvas coords
};

Tablegcell: adt
{
	cell: ref Tablecell;
	drawnhere: int;
};

Tablerow: adt
{
	cells: list of ref Tablecell;
	height: int;
	ascent: int;
	align: Align;
	pos: Point;
	rule: int;			# width of rule below row, if > 0
	ruleids: list of int;	# canvas ids of lines used to draw rule
};

Tablecol: adt
{
	width: int;
	align: Align;
	pos: Point;
	rule: int;			# width of rule to right of col, if > 0
	ruleids: list of int;	# canvas ids of lines used to draw rule
};

Table: adt
{
	nrow: int;
	ncol: int;
	ncell: int;
	width: int;
	height: int;
	capcell: ref Tablecell;
	border: int;
	brectid: int;
	cols: array of ref Tablecol;
	rows: array of ref Tablerow;
	cells: list of ref Tablecell;
	grid: array of array of ref Tablegcell;
	colw: array of int;
	rowh: array of int;
};

# Font stuff

DefaultFnum: con (DefFont*NSIZE + Size10);

fontnames := array[NFONTTAG] of {
	"/fonts/lucidasans/unicode.6.font",
	"/fonts/lucidasans/unicode.7.font",
	"/fonts/lucidasans/unicode.8.font",
	"/fonts/lucidasans/unicode.10.font",
	"/fonts/lucidasans/unicode.13.font",
	"/fonts/lucidasans/italiclatin1.6.font",
	"/fonts/lucidasans/italiclatin1.7.font",
	"/fonts/lucidasans/italiclatin1.8.font",
	"/fonts/lucidasans/italiclatin1.10.font",
	"/fonts/lucidasans/italiclatin1.13.font",
	"/fonts/lucidasans/boldlatin1.6.font",
	"/fonts/lucidasans/boldlatin1.7.font",
	"/fonts/lucidasans/boldlatin1.8.font",
	"/fonts/lucidasans/boldlatin1.10.font",
	"/fonts/lucidasans/boldlatin1.13.font",
	"/fonts/lucidasans/typelatin1.6.font",
	"/fonts/lucidasans/typelatin1.7.font",
	"/fonts/pelm/latin1.9.font",
	"/fonts/pelm/ascii.12.font",
	"/fonts/pelm/ascii.16.font"
};

fontrefs := array[NFONTTAG] of ref Font;
fontused := array[NFONTTAG] of { DefaultFnum => 1, * => 0};

# TABHPAD, TABVPAD are extra space between columns, rows
TABHPAD: con 10;
TABVPAD: con 4;

tab: ref Table;
top: ref Tk->Toplevel;
display: ref Draw->Display;
canv: string;

init(asys: Sys, adraw: Draw, nil: Bufio, atk: Tk, aw: Tkclient)
{
	sys = asys;
	draw = adraw;
	tk = atk;
	tkclient = aw;
	html = load HTML HTML->PATH;
	S = load String String->PATH;
}

create(parent: string, t: ref Tk->Toplevel, name, args: string): string
{
	if(html == nil)
		return "can't load HTML module";
	top = t;
	display = t.image.display;
	canv = name;
	err := tk->cmd(t, "canvas " + canv);
	if(len err > 0 && err[0] == '!')
		return err_ret(err);

	spec: array of ref Lex;
	(spec, err) = getspec(parent, args);
	if(err != "")
		return err_ret(err);

	err = parsetab(spec);
	if(err != "")
		return err_ret(err);

	err = build();
	if(err != "")
		return err_ret(err);
	return "";
}

err_ret(s: string) : string
{
	return Name + ": " + s;
}

getspec(parent, args: string) : (array of ref Lex, string)
{
	(n, argl) := sys->tokenize(args, " ");
	if(n != 1)
		return (nil, "usage: " + Name + " file");
	(filebytes, err) := readfile(fullname(parent, hd argl));
	if(err != "")
		return (nil, err);
	return(html->lex(filebytes, HTML->UTF8, 1), "");
}

readfile(path: string): (array of byte, string)
{
	fd := sys->open(path, sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("can't open %s, the error was: %r", path));
	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return (nil, sys->sprint("can't stat %s, the error was: %r", path));
	if(d.mode & Sys->DMDIR)
		return (nil, sys->sprint("%s is a directory", path));

	l := int d.length;
	buf := array[l] of byte;
	tot := 0;
	while(tot < l) {
		need := l - tot;
		n := sys->read(fd, buf[tot:], need);
		if(n <= 0)
			return (nil, sys->sprint("error reading %s, the error was: %r", path));
		tot += n;
	}
	return (buf, "");
}

# Use HTML 3.2 table spec as external representation
# (But no th cells, width specs; and extra "rule" attribute
# for col and tr meaning that a rule of given width is to
# follow the given column or row).
# DTD elements:
#	table: - O (caption?, col*, tr*)
#	caption: - - (%text+)
#	col: - O empty
#	tr: - O td*
#	td: - O (%body.content)
parsetab(toks: array of ref Lex) : string
{
	tabletlex := toks[0];
	n := len toks;
	(tlex, i) := nexttok(toks, n, 0);

	# caption
	capcell: ref Tablecell = nil;
	if(tlex != nil && tlex.tag == Tcaption) {
		for(j := i+1; j < n; j++) {
			tlex = toks[j];
			if(tlex.tag == Tcaption + RBRA)
				break;
		}
		if(j >= n)
			return syntax_err(tlex, j);
		if(j > i+1) {
			captoks := toks[i+1:j];
			(caplines, e) := lexes2lines(captoks);
			if(e != nil)
				return e;
			# we ignore caption now
#			capcell = ref Tablecell(0, captoks, caplines, 1, 1, 1, Align(Anone, Anone),
#						0, 0, 0, 0, 0, Point(0,0));
		}
		(tlex, i) = nexttok(toks, n, j);
	}

	# col*
	cols: list of ref Tablecol = nil;
	while(tlex != nil && tlex.tag == Tcol) {
		col := makecol(tlex);
		if(col.align.halign == Anone)
			col.align.halign = Aleft;
		cols = col :: cols;
		(tlex, i) = nexttok(toks, n, i);
	}
	cols = revcols(cols);

	body : list of ref Tablerow = nil;
	cells : list of ref Tablecell = nil;
	cellid := 0;
	rows: list of ref Tablerow = nil;

	# tr*
	while(tlex != nil && tlex.tag == Ttr) {
		currow := ref Tablerow(nil, 0, 0, makealign(tlex), Point(0,0), makelinew(tlex, "rule"), nil);
		rows = currow :: rows;

		# td*
		(tlex, i) = nexttok(toks, n, i);
		while(tlex != nil && tlex.tag == Ttd) {
			rowspan := 1;
			(rsfnd, rs) := html->attrvalue(tlex.attr, "rowspan");
			if(rsfnd && rs != "")
				rowspan = int rs;
			colspan := 1;
			(csfnd, cs) := html->attrvalue(tlex.attr, "colspan");
			if(csfnd && cs != "")
				colspan = int cs;
			nowrap := 0;
			(nwfnd, nil) := html->attrvalue(tlex.attr, "nowrap");
			if(nwfnd)
				nowrap = 1;
			align := makealign(tlex);
			for(j := i+1; j < n; j++) {
				tlex = toks[j];
				tg := tlex.tag;
				if(tg == Ttd + RBRA || tg == Ttd || tg == Ttr + RBRA || tg == Ttr)
					break;
			}
			if(j == n)
				tlex = nil;
			content: array of ref Lex = nil;
			if(j > i+1)
				content = toks[i+1:j];
			(lines, err) := lexes2lines(content);
			if(err != "")
				return err;
			curcell := ref Tablecell(cellid, content, lines, rowspan, colspan, nowrap, align, 0, 0, 0, 0, 0, Point(0,0));
			currow.cells = curcell :: currow.cells;
			cells = curcell :: cells;
			cellid++;
			if(tlex != nil && tlex.tag == Ttd + RBRA)
				(tlex, i) = nexttok(toks, n, j);
			else
				i = j;
		}
		if(tlex != nil && tlex.tag == Ttr + RBRA)
			(tlex, i) = nexttok(toks, n, i);
	}
	if(tlex == nil || tlex.tag != Ttable + RBRA)
		return syntax_err(tlex, i);

	# now reverse all the lists that were built in reverse order
	# and calculate nrow, ncol

	rows = revrowl(rows);
	nrow := len rows;
	rowa := array[nrow] of ref Tablerow;
	ncol := 0;
	r := 0;
	for(rl := rows; rl != nil; rl = tl rl) {
		row := hd rl;
		rowa[r++] = row;
		rcols := 0;
		cl := row.cells;
		row.cells = nil;
		while(cl != nil) {
			c := hd cl;
			row.cells = c :: row.cells;
			rcols += c.colspan;
			cl = tl cl;
		}
		if(rcols > ncol)
			ncol = rcols;
	}
	cells = revcelll(cells);

	cola := array[ncol] of ref Tablecol;
	for(c := 0; c < ncol; c++) {
		if(cols != nil) {
			cola[c] = hd cols;
			cols = tl cols;
		}
		else
			cola[c] = ref Tablecol(0, Align(Anone, Anone), Point(0,0), 0, nil);
	}

	if(tabletlex.tag != Ttable)
		return syntax_err(tabletlex, 0);
	border := makelinew(tabletlex, "border");
	tab = ref Table(nrow, ncol, cellid, 0, 0, capcell, border, 0, cola, rowa, cells, nil, nil, nil);

	return "";
}

syntax_err(tlex: ref Lex, i: int) : string
{
	if(tlex == nil)
		return "syntax error in table: premature end";
	else
		return "syntax error in table at token " + string i + ": " + html->lex2string(tlex);
}

# next token after toks[i], skipping whitespace
nexttok(toks: array of ref Lex, ntoks, i: int) : (ref Lex, int)
{
	i++;
	if(i >= ntoks)
		return (nil, i);
	t := toks[i];
	while(t.tag == Data) {
		if(S->drop(t.text, " \t\n\r") != "")
			break;
		i++;
		if(i >= ntoks)
			return (nil, i);
		t = toks[i];
	}
# sys->print("nexttok returning (%s,%d)\n", html->lex2string(t), i);
	return(t, i);
}

makecol(tlex: ref Lex) : ref Tablecol
{
	return ref Tablecol(0, makealign(tlex), Point(0,0), makelinew(tlex, "rule"), nil);
}

makelinew(tlex: ref Lex, aname: string) : int
{
	ans := 0;
	(fnd, val) := html->attrvalue(tlex.attr, aname);
	if(fnd) {
		if(val == "")
			ans = 1;
		else
			ans = int val;
	}
	return ans;
}

makealign(tlex: ref Lex) : Align
{
	(nil,h) := html->attrvalue(tlex.attr, "align");
	(nil,v) := html->attrvalue(tlex.attr, "valign");
	hal := align_val(h, Anone);
	val := align_val(v, Anone);
	return Align(hal, val);
}

align_val(sal: string, dflt: int) : int
{
	ans := dflt;
	case sal {
		"left" => ans = Aleft;
		"center" => ans = Acenter;
		"right" => ans = Aright;
		"justify" => ans = Ajustify;
		"top" => ans = Atop;
		"middle" => ans = Amiddle;
		"bottom" => ans = Abottom;
		"baseline" => ans = Abaseline;
	}
	return ans;
}

revcols(l : list of ref Tablecol) : list of ref Tablecol
{
	ans : list of ref Tablecol = nil;
	while(l != nil) {
		ans = hd l :: ans;
		l = tl l;
	}
	return ans;
}

revrowl(l : list of ref Tablerow) : list of ref Tablerow
{
	ans : list of ref Tablerow = nil;
	while(l != nil) {
		ans = hd l :: ans;
		l = tl l;
	}
	return ans;
}

revcelll(l : list of ref Tablecell) : list of ref Tablecell
{
	ans : list of ref Tablecell = nil;
	while(l != nil) {
		ans = hd l :: ans;
		l = tl l;
	}
	return ans;
}

revintl(l : list of int) : list of int
{
	ans : list of int = nil;
	while(l != nil) {
		ans = hd l :: ans;
		l = tl l;
	}
	return ans;
}

# toks should contain only Font (i.e., size) and style changes, along with text.
lexes2lines(toks: array of ref Lex) : (ref Line, string)
{
	n := len toks;
	(tlex, i) := nexttok(toks, n, -1);
	ans: ref Line = nil;
	if(tlex == nil)
		return(ans, "");
	curline : ref Line = nil;
	curitem : ref Item = nil;
	stylestk := DefFont :: nil;
	sizestk := DefSize :: nil;
	f := DefaultFnum;
	fontstk:= f :: nil;
	for(;;) {
		if(i >= n)
			break;
		tlex = toks[i++];
		case tlex.tag {
		Data =>
			text := tlex.text;
			while(text != "") {
				if(curline == nil) {
					curline = ref Line(nil, Point(0,0), 0, 0, 0, nil, nil);
					ans = curline;
				}
				s : string;
				(s, text) = S->splitl(text, "\n");
				if(s != "") {
					f = hd fontstk;
					it := ref Item(0, s, f, Point(0,0), 0, curline, curitem, nil);
					if(curitem == nil)
						curline.items = it;
					else
						curitem.next = it;
					curitem = it;
				}
				if(text != "") {
					text = text[1:];
					curline.next = ref Line(nil, Point(0,0), 0, 0, 0, nil, nil);
					curline = curline.next;
					curitem = nil;
				}
			}
		HTML->Tfont =>
			(fnd, ssize) := html->attrvalue(tlex.attr, "size");
			if(fnd && len ssize > 0) {
				# HTML size 3 == our Size10
				sz := (int ssize) + (Size10 - 3);
				if(sz < 0 || sz >= NSIZE)
					return (nil, "bad font size " + ssize);
				sizestk = sz :: sizestk;
				fontstk = fnum(hd stylestk, sz) :: fontstk;
			}
			else
				return (nil, "bad font command: no size");
		HTML->Tfont + RBRA =>
			fontstk = tl fontstk;
			sizestk = tl sizestk;
			if(sizestk == nil)
				return (nil, "unmatched </FONT>");
		HTML->Tb =>
			stylestk = Bold :: stylestk;
			fontstk = fnum(Bold, hd sizestk) :: fontstk;
		HTML->Ti =>
			stylestk = Italic :: stylestk;
			fontstk = fnum(Italic, hd sizestk) :: fontstk;
		HTML->Ttt =>
			stylestk = Type :: stylestk;
			fontstk = fnum(Type, hd sizestk) :: fontstk;
		HTML->Tb + RBRA or HTML->Ti + RBRA or HTML->Ttt + RBRA =>
			fontstk = tl fontstk;
			stylestk = tl stylestk;
			if(stylestk == nil)
				return (nil, "unmatched </B>, </I>, or </TT>");
		}
	}
	return (ans, "");
}

fnum(fstyle, fsize: int) : int
{
	ans := fstyle*NSIZE + fsize;
	fontused[ans] = 1;
	return ans;
}

loadfonts() : string
{
	for(i := 0; i < NFONTTAG; i++) {
		if(fontused[i] && fontrefs[i] == nil) {
			fname := fontnames[i];
			f := Font.open(display, fname);
			if(f == nil)
				return sys->sprint("can't open font %s: %r", fname);
			fontrefs[i] = f;
		}
	}
	return "";
}

# Find where each cell goes in nrow x ncol grid
setgrid()
{
	gcells := array[tab.nrow] of { * => array[tab.ncol] of { * => ref Tablegcell(nil, 1)} };

	# The following arrays keep track of cells that are spanning
	# multiple rows;  rowspancnt[i] is the number of rows left
	# to be spanned in column i.
	# When done, cell's (row,col) is upper left grid point.
	rowspancnt := array[tab.ncol] of { * => 0};
	rowspancell := array[tab.ncol] of ref Tablecell;

	ri := 0;
	ci := 0;
	for(ri = 0; ri < tab.nrow; ri++) {
		row := tab.rows[ri];
		cl := row.cells;
		for(ci = 0; ci < tab.ncol; ) {
			if(rowspancnt[ci] > 0) {
				gcells[ri][ci].cell = rowspancell[ci];
				gcells[ri][ci].drawnhere = 0;
				rowspancnt[ci]--;
				ci++;
			}
			else {
				if(cl == nil) {
					ci++;
					continue;
				}
				c := hd cl;
				cl = tl cl;
				cspan := c.colspan;
				if(cspan == 0) {
					cspan = tab.ncol - ci;
					c.colspan = cspan;
				}
				rspan := c.rowspan;
				if(rspan == 0) {
					rspan = tab.nrow - ri;
					c.rowspan = rspan;
				}
				c.row = ri;
				c.col = ci;
				for(i := 0; i < cspan && ci < tab.ncol; i++) {
					gcells[ri][ci].cell = c;
					if(i > 0)
						gcells[ri][ci].drawnhere = 0;
					if(rspan > 1) {
						rowspancnt[ci] = rspan-1;
						rowspancell[ci] = c;
					}
					ci++;
				}
			}
		}
	}
	tab.grid = gcells;
}

build() : string
{
	ri, ci: int;

#	sys->print("\n\ninitial table\n"); printtable();
	if(tab.ncol == 0 || tab.nrow == 0)
		return "";

	setgrid();

	err := loadfonts();
	if(err != "")
		return err;

	for(cl := tab.cells; cl != nil; cl = tl cl)
		cell_geom(hd cl);

	for(ci = 0; ci < tab.ncol; ci++)
		col_geom(ci);

	for(ri = 0; ri < tab.nrow; ri++)
		row_geom(ri);

	caption_geom();

	table_geom();
#	sys->print("\n\ntable after geometry set\n"); printtable();

	h := tab.height;
	w := tab.width;
	if(tab.capcell != nil) {
		h += tab.capcell.height;
		if(tab.capcell.width > w)
			w = tab.capcell.width;
	}

	err = tk->cmd(top, canv + " configure -width " + string w
		+ " -height " + string h);
	if(len err > 0 && err[0] == '!')
		return err;
	err = create_cells();
	if(err != "")
		return err;
	err = create_border();
	if(err != "")
		return err;
	err = create_rules();
	if(err != "")
		return err;
	err = create_caption();
	if(err != "")
		return err;
	tk->cmd(top, "update");

	return "";
}

create_cells() : string
{
	for(cl := tab.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		cpos := c.pos;
		for(l := c.lines; l != nil; l = l.next) {
			lpos := l.pos;
			for(it := l.items; it != nil; it = it.next) {
				ipos := it.pos;
				pos := ipos.add(lpos.add(cpos));
				fnt := fontrefs[it.fontnum];
				v := tk->cmd(top, canv + " create text " + string pos.x + " "
					+ string pos.y + " -anchor nw -font " + fnt.name
					+ " -text '" + it.s);
				if(len v > 0 && v[0] == '!')
					return v;
				it.itemid = int v;
			}
		}
	}
	return "";
}

create_border() : string
{
	bd := tab.border;
	if(bd > 0) {
		x1 := string (bd / 2);
		y1 := x1;
		x2 := string (tab.width - bd/2 -1);
		y2 := string (tab.height - bd/2 -1);
		v := tk->cmd(top, canv + " create rectangle "
			+ x1 + " " + y1 + " " + x2 + " " + y2 + " -width " + string bd);
		if(len v > 0 && v[0] == '!')
			return v;
		tab.brectid = int v;
	}
	return "";
}

create_rules() : string
{
	ci, ri, i: int;
	err : string;
	c : ref Tablecell;
	for(ci = 0; ci < tab.ncol; ci++) {
		col := tab.cols[ci];
		rw := col.rule;
		if(rw > 0) {
			x := col.pos.x + col.width + TABHPAD/2 - rw/2;
			ids: list of int = nil;
			startri := 0;
			for(ri = 0; ri < tab.nrow; ri++) {
				c = tab.grid[ri][ci].cell;
				if(c.col+c.colspan-1 > ci) {
					# rule would cross a spanning cell at this column
					if(ri > startri) {
						(err, i) = create_col_rule(startri, ri-1, x, rw);
						if(err != "")
							return err;
						ids = i :: ids;
					}
					startri = ri+1;
				}
			}
			if(ri > startri)
				(err, i) = create_col_rule(startri, ri-1, x, rw);
			ids = i :: ids;
			col.ruleids = revintl(ids);
		}
	}
	for(ri = 0; ri < tab.nrow; ri++) {
		row := tab.rows[ri];
		rw := row.rule;
		if(rw > 0) {
			y := row.pos.y + row.height + TABVPAD/2 - rw/2;
			ids: list of int = nil;
			startci := 0;
			for(ci = 0; ci < tab.ncol; ci++) {
				c = tab.grid[ri][ci].cell;
				if(c.row+c.rowspan-1 > ri) {
					# rule would cross a spanning cell at this row
					if(ci > startci) {
						(err, i) = create_row_rule(startci, ci-1, y, rw);
						if(err != "")
							return err;
						ids = i :: ids;
					}
					startci = ci+1;
				}
			}
			if(ci > startci)
				(err, i) = create_row_rule(startci, ci-1, y, rw);
			ids = i :: ids;
			row.ruleids = revintl(ids);
		}
	}
	return "";
}

create_col_rule(topri, botri, x, rw: int) : (string, int)
{
	y1, y2: int;
	if(topri == 0)
		y1 = 0;
	else
		y1 = tab.rows[topri].pos.y - TABVPAD/2;
	if(botri == tab.nrow-1)
		y2 = tab.height;
	else
		y2 = tab.rows[botri].pos.y + tab.rows[botri].height + TABVPAD/2;
	sx := string x;
	v := tk->cmd(top, canv + " create line " + sx + " "
		+ string y1 + " " + sx + " " + string y2 + " -width " + string rw);
	if(len v > 0 && v[0] == '!')
		return (v, 0);
	return ("", int v);
}

create_row_rule(leftci, rightci, y, rw: int) : (string, int)
{
	x1, x2: int;
	if(leftci == 0)
		x1 = 0;
	else
		x1 = tab.cols[leftci].pos.x - TABHPAD/2;
	if(rightci == tab.ncol-1)
		x2 = tab.width;
	else
		x2 = tab.cols[rightci].pos.x + tab.cols[rightci].width + TABHPAD/2;
	sy := string y;
	v := tk->cmd(top, canv + " create line " + string x1 + " "
		+ sy + " " + string x2 + " " + sy + " -width " + string rw);
	if(len v > 0 && v[0] == '!')
		return (v, 0);
	return ("", int v);
}

create_caption() : string
{
	if(tab.capcell == nil)
		return "";
	cpos := Point(0, tab.height + 2*TABVPAD);
	for(l := tab.capcell.lines; l != nil; l = l.next) {
		lpos := l.pos;
		for(it := l.items; it != nil; it = it.next) {
			ipos := it.pos;
			pos := ipos.add(lpos.add(cpos));
			fnt := fontrefs[it.fontnum];
			v := tk->cmd(top, canv + " create text " + string pos.x + " "
				+ string pos.y + " -anchor nw -font " + fnt.name
				+ " -text '" + it.s);
			if(len v > 0 && v[0] == '!')
				return v;
			it.itemid = int v;
		}
	}
	return "";
}

# Assuming row and col geoms correct, set row, col, and cell origins
table_geom()
{
	row: ref Tablerow;
	col: ref Tablecol;
	orig := Point(0,0);
	bd := tab.border;
	if(bd > 0)
		orig = orig.add(Point(TABHPAD+bd, TABVPAD+bd));
	o := orig;
	for(ci := 0; ci < tab.ncol; ci++) {
		col = tab.cols[ci];
		col.pos = o;
		o.x += col.width + col.rule;
		if(ci < tab.ncol-1)
			o.x += TABHPAD;
	}
	if(bd > 0)
		o.x += TABHPAD + bd;
	tab.width = o.x;

	o = orig;
	for(ri := 0; ri < tab.nrow; ri++) {
		row = tab.rows[ri];
		row.pos = o;
		o.y += row.height + row.rule;
		if(ri < tab.nrow-1)
			o.y += TABVPAD;
	}
	if(bd > 0)
		o.y += TABVPAD + bd;
	tab.height = o.y;

	if(tab.capcell != nil) {
		tabw := tab.width;
		if(tab.capcell.width > tabw)
			tabw = tab.capcell.width;
		for(l := tab.capcell.lines; l != nil; l = l.next)
			l.pos.x += (tabw - l.width)/2;
	}

	for(cl := tab.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		row = tab.rows[c.row];
		col = tab.cols[c.col];
		x := col.pos.x;
		y := row.pos.y;
		w := spanned_col_width(c.col, c.col+c.colspan-1);
		case (cellhalign(c)) {
		Aright =>
			x += w - c.width;
		Acenter =>
			x += (w - c.width) / 2;
		}
		h := spanned_row_height(c.row, c.row+c.rowspan-1);
		case (cellvalign(c)) {
		Abottom =>
			y += h - c.height;
		Anone or Amiddle =>
			y += (h - c.height) / 2;
		Abaseline =>
			y += row.ascent - c.ascent;
		}
		c.pos = Point(x,y);
	}
}

spanned_col_width(firstci, lastci: int) : int
{
	firstcol := tab.cols[firstci];
	if(firstci == lastci)
		return firstcol.width;
	lastcol := tab.cols[lastci];
	return (lastcol.pos.x + lastcol.width - firstcol.pos.x);
}

spanned_row_height(firstri, lastri: int) : int
{
	firstrow := tab.rows[firstri];
	if(firstri == lastri)
		return firstrow.height;
	lastrow := tab.rows[lastri];
	return (lastrow.pos.y + lastrow.height - firstrow.pos.y);
}

# Assuming cell geoms are correct, set col widths.
# This code is sloppy for spanned columns;
# it will allocate too much space for them because
# inter-column pad is ignored, and it may make
# narrow columns wider than they have to be.
col_geom(ci: int)
{
	col := tab.cols[ci];
	col.width = 0;
	for(ri := 0; ri < tab.nrow; ri++) {
		c := tab.grid[ri][ci].cell;
		if(c == nil)
			continue;
		cwd := c.width / c.colspan;
		if(cwd > col.width)
			col.width = cwd;
	}
}

# Assuming cell geoms are correct, set row heights
row_geom(ri: int)
{
	row := tab.rows[ri];
	# find rows's global height and ascent
	h := 0;
	a := 0;
	n : int;
	for(cl := row.cells; cl != nil; cl = tl cl) {
		c := hd cl;
		al := cellvalign(c);
		if(al == Abaseline) {
			n = c.ascent;
			if(n > a) {
				h += (n - a);
				a = n;
			}
			n = c.height - c.ascent;
			if(n > h-a)
				h = a + n;
		}
		else {
			n = c.height;
			if(n > h)
				h = n;
		}
	}
	row.height = h;
	row.ascent = a;
}

cell_geom(c: ref Tablecell)
{
	width := 0;
	o := Point(0,0);
	for(l := c.lines; l != nil; l = l.next) {
		line_geom(l, o);
		o.y += l.height;
		if(l.width > width)
			width = l.width;
	}
	c.width = width;
	c.height = o.y;
	if(c.lines != nil)
		c.ascent = c.lines.ascent;
	else
		c.ascent = 0;

	al := cellhalign(c);
	if(al == Acenter || al == Aright) {
		for(l = c.lines; l != nil; l = l.next) {
			xdelta := c.width - l.width;
			if(al == Acenter)
				xdelta /= 2;
			l.pos.x += xdelta;
		}
	}
}

caption_geom()
{
	if(tab.capcell != nil) {
		o := Point(0,TABVPAD);
		width := 0;
		for(l := tab.capcell.lines; l != nil; l = l.next) {
			line_geom(l, o);
			o.y += l.height;
			if(l.width > width)
				width = l.width;
		}
		tab.capcell.width = width;
		tab.capcell.height = o.y + 4*TABVPAD;
	}
}

line_geom(l: ref Line, o: Point)
{
	# find line's global height and ascent
	h := 0;
	a := 0;
	for(it := l.items; it != nil; it = it.next) {
		fnt := fontrefs[it.fontnum];
		n := fnt.ascent;
		if(n > a) {
			h += (n - a);
			a = n;
		}
		n = fnt.height - fnt.ascent;
		if(n > h-a)
			h = a + n;
	}
	l.height = h;
	l.ascent = a;
	# set positions
	l.pos = o;
	for(it = l.items; it != nil; it = it.next) {
		fnt := fontrefs[it.fontnum];
		it.width = fnt.width(it.s);
		it.pos.x = o.x;
		o.x += it.width;
		it.pos.y = a - fnt.ascent;
	}
	l.width = o.x;
}

cellhalign(c: ref Tablecell) : int
{
	a := c.align.halign;
	if(a == Anone)
		a = tab.cols[c.col].align.halign;
	return a;
}

cellvalign(c: ref Tablecell) : int
{
	a := c.align.valign;
	if(a == Anone)
		a = tab.rows[c.row].align.valign;
	return a;
}

# table debugging
printtable()
{
	if(tab == nil) {
		sys->print("no table\n");
		return;
	}
	sys->print("Table %d rows, %d cols width %d height %d\n",
			tab.nrow, tab.ncol, tab.width, tab.height);
	if(tab.capcell != nil)
		sys->print("  caption: "); printlexes(tab.capcell.content, "    ");
	sys->print("  cols:\n"); printcols(tab.cols);
	sys->print("  rows:\n"); printrows(tab.rows);
}

align2string(al: int) : string
{
	s := "";
	case al {
		Anone => s = "none";
		Aleft => s = "left";
		Acenter => s = "center";
		Aright => s = "right";
		Ajustify => s = "justify";
		Atop => s = "top";
		Amiddle => s = "middle";
		Abottom => s = "bottom";
		Abaseline => s = "baseline";
	}
	return s;
}

printcols(cols: array of ref Tablecol)
{
	n := len cols;
	for(i := 0 ; i < n; i++) {
		c := cols[i];
		sys->print(" width %d align = %s,%s pos (%d,%d) rule %d\n", c.width,
			align2string(c.align.halign), align2string(c.align.valign), c.pos.x, c.pos.y, c.rule);
	}
}

printrows(rows: array of ref Tablerow)
{
	n := len rows;
	for(i := 0; i < n; i++) {
		tr := rows[i];
		sys->print("      row height %d ascent %d align=%s,%s pos (%d,%d) rule %d\n", tr.height, tr.ascent,
			align2string(tr.align.halign), align2string(tr.align.valign), tr.pos.x, tr.pos.y, tr.rule);
		for(cl := tr.cells; cl != nil; cl = tl cl) {
			c := hd cl;
			sys->print("        cell %d width %d height %d ascent %d align=%s,%s\n",
				c.cellid, c.width, c.height, c.ascent,
				align2string(c.align.halign), align2string(c.align.valign));
			sys->print("             pos (%d,%d) rowspan=%d colspan=%d nowrap=%d\n",
				c.pos.x, c.pos.y, c.rowspan, c.colspan, c.nowrap);
			printlexes(c.content, "        ");
			printlines(c.lines);
		}
	}
}

printlexes(lexes: array of ref Lex, indent: string)
{
	for(i := 0; i < len lexes; i++)
		sys->print("%s%s\n", indent, html->lex2string(lexes[i]));
}

printlines(l: ref Line)
{
	if(l == nil)
		return;
	sys->print("lines: \n");
	while(l != nil) {
		sys->print("          Line: pos (%d,%d), height %d ascent %d\n", l.pos.x, l.pos.y, l.height, l.ascent);
		printitems(l.items);
		l = l.next;
	}
}

printitems(i: ref Item)
{
	while(i != nil) {
		sys->print("            '%s' id %d fontnum %d w %d, pos (%d,%d)\n", i.s, i.itemid, i.fontnum,
			i.width, i.pos.x, i.pos.y);
		i = i.next;
	}
}

printgrid(g: array of array of ref Tablegcell)
{
	nr := len g;
	nc := len g[0];
	for(r := 0; r < nr; r++) {
		for(c := 0; c < nc; c++) {
			x := g[r][c];
			cell := x.cell;
			suf := " ";
			if(x.drawnhere == 0)
				suf = "*";
			if(cell == nil)
				sys->print("     %s", suf);
			else
				sys->print("%5d%s", cell.cellid, suf);
		}
		sys->print("\n");
	}
}

# Return (table in correct format, error string)
cook(parent: string, fmt: int, args: string) : (ref Celem, string)
{
	(spec, err) := getspec(parent, args);
	if(err != "")
		return (nil, err);
	if(fmt == FHtml)
		return cookhtml(spec);
	else
		return cooklatex(spec);
}

# Return (table as latex, error string)
# BUG: cells spanning multiple rows not handled correctly
# (all their contents go in the first row of span, though hrules properly broken)
cooklatex(spec: array of ref Lex) : (ref Celem, string)
{
	s : string;
	ci, ri: int;
	err := parsetab(spec);
	if(err != "")
		return (nil, err_ret(err));

	setgrid();

	ans := ref Celem(SGML, "", nil, nil, nil, nil);
	cur : ref Celem = nil;
	cur = add(ans, cur, specialce("\\begin{tabular}[t]{" + lcolspec() + "}\n"));
	if(tab.border) {
		if(tab.border == 1)
			s = "\\hline\n";
		else
			s = "\\hline\\hline\n";
		cur = add(ans, cur, specialce(s));
	}
	for(ri = 0; ri < tab.nrow; ri++) {
		row := tab.rows[ri];
		ci = 0;
		anyrowspan := 0;
		for(cl := row.cells; cl != nil; cl = tl cl) {
			c := hd cl;
			while(ci < c.col) {
				cur = add(ans, cur, specialce("&"));
				ci++;
			}
			mcol := 0;
			if(c.colspan > 1) {
				cur = add(ans, cur, specialce("\\multicolumn{" + string c.colspan + "}{" +
						lnthcolspec(ci, ci+c.colspan-1, c.align.halign) + "}{"));
				mcol = 1;
			}
			else if(c.align.halign != Anone) {
				cur = add(ans, cur, specialce("\\multicolumn{1}{" +
						lnthcolspec(ci, ci, c.align.halign) + "}{"));
				mcol = 1;
			}
			if(c.rowspan > 1)
				anyrowspan = 1;
			cur = addlconvlines(ans, cur, c);
			if(mcol) {
				cur = add(ans, cur, specialce("}"));
				ci += c.colspan-1;
			}
		}
		while(ci++ < tab.ncol-1)
			cur = add(ans, cur, specialce("&"));
		if(ri < tab.nrow-1 || row.rule > 0 || tab.border > 0)
			cur = add(ans, cur, specialce("\\\\\n"));
		if(row.rule) {
			if(anyrowspan) {
				startci := 0;
				for(ci = 0; ci < tab.ncol; ci++) {
					c := tab.grid[ri][ci].cell;
					if(c.row+c.rowspan-1 > ri) {
						# rule would cross a spanning cell at this row
						if(ci > startci)
							cur = add(ans, cur, specialce("\\cline{" +
								string (startci+1) + "-" + string ci + "}"));
						startci = ci+1;
					}
				}
				if(ci > startci)
					cur = add(ans, cur, specialce("\\cline{" +
						string (startci+1) + "-" + string ci + "}"));
			}
			else
				cur = add(ans, cur, specialce("\\hline\n"));
		}
	}
	if(tab.border) {
		if(tab.border == 1)
			s = "\\hline\n";
		else
			s = "\\hline\\hline\n";
		cur = add(ans, cur, specialce(s));
	}
	cur = add(ans, cur, specialce("\\end{tabular}\n"));

	if(ans != nil)
		ans = ans.contents;
	return (ans, "");
}

lcolspec() : string
{
	ans := "";
	for(ci := 0; ci < tab.ncol; ci++)
		ans += lnthcolspec(ci, ci, Anone);
	return ans;
}

lnthcolspec(ci, cie, al: int) : string
{
	ans := "";
	if(ci == 0) {
		if(tab.border == 1)
			ans = "|";
		else if(tab.border > 1)
			ans = "||";
	}
	col := tab.cols[ci];
	if(al == Anone)
		al = col.align.halign;
	case al {
	Acenter =>
		ans += "c";
	Aright =>
		ans += "r";
	* =>
		ans += "l";
	}
	if(ci == cie) {
		if(col.rule == 1)
			ans += "|";
		else if(col.rule > 1)
			ans += "||";
	}
	if(cie == tab.ncol - 1) {
		if(tab.border == 1)
			ans += "|";
		else if(tab.border > 1)
			ans += "||";
	}
	return ans;
}

addlconvlines(par, tail: ref Celem, c: ref Tablecell) : ref Celem
{
	line := c.lines;
	if(line == nil)
		return tail;
	multiline := 0;
	if(line.next != nil) {
		multiline = 1;
		val := "";
		case cellvalign(c) {
		Abaseline or Atop => val = "[t]";
		Abottom => val = "[b]";
		}
		hal := "l";
		case cellhalign(c) {
		Aright => hal = "r";
		Acenter => hal = "c";
		}
		# The @{}'s in the colspec eliminate extra space before and after result
		tail = add(par, tail, specialce("\\begin{tabular}" + val + "{@{}" + hal + "@{}}\n"));
	}
	while(line != nil) {
		for(it := line.items; it != nil; it = it.next) {
			fnum := it.fontnum;
			f := fnum / NSIZE;
			sz := fnum % NSIZE;
			grouped := 0;
			if((f != DefFont || sz != DefSize) && (it.prev!=nil || it.next!=nil)) {
				tail = add(par, tail, specialce("{"));
				grouped = 1;
			}
			if(f != DefFont) {
				fcmd := "";
				case f {
				Roman => fcmd = "\\rmfamily ";
				Italic => fcmd = "\\itshape ";
				Bold => fcmd = "\\bfseries ";
				Type => fcmd = "\\ttfamily ";
				}
				tail = add(par, tail, specialce(fcmd));
			}
			if(sz != DefSize) {
				szcmd := "";
				case sz {
				Size6 => szcmd = "\\footnotesize ";
				Size8 => szcmd = "\\small ";
				Size10 => szcmd = "\\normalsize ";
				Size12 => szcmd = "\\large ";
				Size16 => szcmd = "\\Large ";
				}
				tail = add(par, tail, specialce(szcmd));
			}
			tail = add(par, tail, textce(it.s));
			if(grouped)
				tail = add(par, tail, specialce("}"));
		}
		ln := line.next;
		if(multiline && ln != nil)
			tail = add(par, tail, specialce("\\\\\n"));
		line = line.next;
	}
	if(multiline)
		tail = add(par, tail, specialce("\\end{tabular}\n"));
	return tail;
}

# Return (table as html, error string)
cookhtml(spec: array of ref Lex) : (ref Celem, string)
{
	n := len spec;
	ans := ref Celem(SGML, "", nil, nil, nil, nil);
	cur : ref Celem = nil;
	for(i := 0; i < n; i++) {
		tok := spec[i];
		if(tok.tag == Data)
			cur = add(ans, cur, textce(tok.text));
		else {
			s := html->lex2string(spec[i]);
			cur = add(ans, cur, specialce(s));
		}
	}
	if(ans != nil)
		ans = ans.contents;
	return (ans, "");
}

textce(s: string) : ref Celem
{
	return ref Celem(Text, s, nil, nil, nil, nil);
}

specialce(s: string) : ref Celem
{
	return ref Celem(Special, s, nil, nil, nil, nil);
}

add(par, tail: ref Celem, e: ref Celem) : ref Celem
{
	if(tail == nil) {
		par.contents = e;
		e.parent = par;
	}
	else
		tail.next = e;
	e.prev = tail;
	return e;
}

fullname(parent, file: string): string
{
	if(len parent==0 || (len file>0 && (file[0]=='/' || file[0]=='#')))
		return file;

	for(i:=len parent-1; i>=0; i--)
		if(parent[i] == '/')
			return parent[0:i+1] + file;
	return file;
}
