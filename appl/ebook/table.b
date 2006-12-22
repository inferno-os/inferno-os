implement Table;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "table.m";

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
}

newcell(w: string, span: Draw->Point): ref Cell
{
	return ref Cell(w, span, (0, 0));
}

layout(cells: array of array of ref Cell, win: ref Tk->Toplevel, w: string)
{
	if (len cells == 0)
		return;
	dim := Point(len cells, len cells[0]);
	for (y := 0; y < dim.y; y++) {
		for (x := 0; x < dim.x; x++) {
			cell := cells[x][y];
			# XXX should take into account cell padding
			if (cell != nil) {
				cell.sizereq = getsize(win, cell.w);
# sys->print("cell %d %d size %s span %s\n", x, y, p2s(cell.sizereq), p2s(cell.span));
			}
#  else
# sys->print("cell %d %d blank\n", x, y);
		}
	}

	colwidths := array[dim.x] of {* => 0};
	# calculate column widths (ignoring multi-column cells)
	for (x := 0; x < dim.x; x++) {
		for (y = 0; y < dim.y; y++) {
			cell := cells[x][y];
			if (cell != nil && cell.span.x == 1 && cell.sizereq.x > colwidths[x])
				colwidths[x] = cell.sizereq.x;
		}
	}

	# now check that multi-column cells fit in their columns
	colexpand := array[dim.x] of {* => 1};
	for (x = 0; x < dim.x; x++) {
		for (y = 0; y < dim.y; y++) {
			cell := cells[x][y];
			if (cell != nil && cell.span.x > 1)
				expandwidths(x, cell.sizereq.x, cell.span.x, colwidths, colexpand);
		}
	}
	colexpand = nil;

	rowheights := array[dim.y] of {* => 0};
	# calculate row heights (ignoring multi-row cells)
	for (y = 0; y < dim.y; y++) {
		for (x = 0; x < dim.x; x++) {
			cell := cells[x][y];
			if (cell != nil && cell.span.y == 1 && cell.sizereq.y > rowheights[y])
				rowheights[y] = cell.sizereq.y;
		}
	}

# 	for (i := 0; i < len colwidths; i++)
# 		sys->print("colwidth %d -> %d\n", i, colwidths[i]);
# 	for (i = 0; i < len rowheights; i++)
# 		sys->print("rowheight %d -> %d\n", i, rowheights[i]);

	rowexpand := array[dim.y] of {* => 1};
	# now check that multi-row cells fit in their columns
	for (y = 0; y < dim.y; y++) {
		for (x = 0; x < dim.x; x++) {
			cell := cells[x][y];
			if (cell != nil && cell.span.y > 1)
				expandwidths(y, cell.sizereq.y, cell.span.y, rowheights, rowexpand);
		}
	}

#	if (rowequalise)
#		equalise(rowheights, dim.y);

#	if (colequalise)
#		equalise(colwidths, dim.x);

	# calculate total width and height (including cell padding)
	totsize := Point(0, 0);
	for (x = 0; x < dim.x; x++)
		totsize.x += colwidths[x];
	for (y = 0; y < dim.y; y++)
		totsize.y += rowheights[y];

	cmd(win, "canvas " + w + " -width " + string totsize.x + " -bg white -height " + string totsize.y);
	p := Point(0, 0);
	for (y = 0; y < dim.y; y++) {
		p.x = 0;
		for (x = 0; x < dim.x; x++) {
			cell := cells[x][y];
			if (cell != nil) {
				cellsize := Point(0, 0);
				span := cell.span;
				for (xx := 0; xx < span.x; xx++)
					cellsize.x += colwidths[x + xx];
				for (yy := 0; yy < span.y; yy++)
					cellsize.y += rowheights[y + yy];
# sys->print("cell [%d %d] %d %d +[%d %d]\n", x, y, p.x, p.y, cellsize.x, cellsize.y);
				cmd(win, w + " create window " + p2s(p) +
					" -anchor nw -window " + cell.w +
					" -width " + string cellsize.x +
					" -height " + string cellsize.y);
			}
			p.x += colwidths[x];
		}
		p.y += rowheights[y];
	}
}

expandwidths(x: int, cellwidth, xcells: int, widths: array of int, expand: array of int)
{
	# find out total space available for cell
	share := 0;
	tot := 0;
	endx := x + xcells;
	for (xx := x; xx < endx; xx++) {
		tot += widths[xx];
		if (expand[xx])
			share++;
	}
	slack := cellwidth - tot;

	# if enough space, then nothing to do.
	if (slack <= 0)
		return;

	# allocate extra space amongst all cols that
	# want to expand. (if any do, otherwise share it
	# out between all of them)
	if (share == 0)
		share = xcells;
	for (xx = x; xx < endx; xx++) {
		m := slack / share;
		widths[xx] += m;
		slack -= m;
		share--;
	}
}

getsize(win: ref Tk->Toplevel, w: string): Point
{
	bd := 2 * int cmd(win, w + " cget -bd");
	return Point(int cmd(win, w + " cget -width") + bd,
			int cmd(win, w + " cget -height") + bd);
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

cmd(win: ref Tk->Toplevel, s: string): string
{
#	sys->print("%ux	%s\n", win, s);
	r := tk->cmd(win, s);
	if (len r > 0 && r[0] == '!') {
		sys->fprint(sys->fildes(2), "error executing '%s': %s\n", s, r);
		raise "tk error";
	}
	return r;
}
