#include "lib9.h"
#include "draw.h"
#include "tk.h"

/*
 * XXX TODO
 * - grid rowcget|columncget
 * - grid columnconfigure/rowconfigure accepts a list of indexes?
 */

#define	O(t, e)		((long)(&((t*)0)->e))

typedef struct TkGridparam TkGridparam;
typedef struct TkBeamparam TkBeamparam;

struct TkGridparam{
	Point	span;
	Tk*	in;
	Point	pad;
	Point ipad;
	char	*row;
	char *col;
	int	sticky;
};

struct TkBeamparam{
	int	minsize;
	int	maxsize;
	int	weight;
	int	pad;
	char	*name;
	int	equalise;
};

static
TkOption opts[] =
{
	"padx",		OPTnndist,	O(TkGridparam, pad.x),	nil,
	"pady",		OPTnndist,	O(TkGridparam, pad.y),	nil,
	"ipadx",	OPTnndist,	O(TkGridparam, ipad.x),	nil,
	"ipady",	OPTnndist,	O(TkGridparam, ipad.y),	nil,
	"in",		OPTwinp,		O(TkGridparam, in),		nil,
	"row",	OPTtext,		O(TkGridparam, row), nil,
	"column",	OPTtext,		O(TkGridparam, col), nil,
	"rowspan",	OPTnndist,	O(TkGridparam, span.y), nil,
	"columnspan",	OPTnndist,	O(TkGridparam, span.x), nil,
	"sticky",	OPTsticky,		O(TkGridparam, sticky), nil,
	nil
};

static
TkOption beamopts[] =
{
	"minsize",		OPTnndist,	O(TkBeamparam, minsize),	nil,
	"maxsize",	OPTnndist,	O(TkBeamparam, maxsize),	nil,
	"weight",		OPTnndist,	O(TkBeamparam, weight),	nil,
	"pad",		OPTnndist,	O(TkBeamparam, pad),		nil,
	"name",		OPTtext,		O(TkBeamparam, name),		nil,
	"equalise",	OPTstab,		O(TkBeamparam, equalise),	tkbool,
	nil
};

void
printgrid(TkGrid *grid)
{
	int x, y;
	Point dim;

	dim = grid->dim;
	print("grid %P\n", grid->dim);
	print("  row heights: ");
	for(y = 0; y < dim.y; y++)
		print("%d[%d,%d,w%d,p%d]%s ",
			grid->rows[y].act,
			grid->rows[y].minsize,
			grid->rows[y].maxsize < 0x7fffffff ? grid->rows[y].maxsize : -1,
			grid->rows[y].weight,
			grid->rows[y].pad,
			grid->rows[y].name ? grid->rows[y].name : "");
	print("\n");
	print("  col widths: ");
	for(x = 0; x < dim.x; x++)
		print("%d[%d,%d,w%d,p%d]%s ",
			grid->cols[x].act,
			grid->cols[x].minsize,
			grid->cols[x].maxsize < 0x7fffffff ? grid->cols[x].maxsize : -1,
			grid->cols[x].weight,
			grid->cols[x].pad,
			grid->cols[x].name ? grid->cols[x].name : "");
	print("\n");
	for(y = 0; y < dim.y; y++){
		print("  row %d: ", y);
		for(x = 0; x < dim.x; x++){
			print("%p;", grid->cells[y][x].tk);
			print("%s%P\t", grid->cells[y][x].tk?grid->cells[y][x].tk->name->name:"(nil)",
				grid->cells[y][x].span);
		}
		print("\n");
	}
}

static void
tkgridsetopt(TkGridparam *p, Tk *tk)
{
	if(p->pad.x != -1)
		tk->pad.x = p->pad.x*2;
	if(p->pad.y != -1)
		tk->pad.y = p->pad.y*2;
	if(p->ipad.x != -1)
		tk->ipad.x = p->ipad.x*2;
	if(p->ipad.y != -1)
		tk->ipad.y = p->ipad.y*2;
	if(p->sticky != -1)
		tk->flag = (tk->flag & ~(Tkanchor|Tkfill)) | (p->sticky & (Tkanchor|Tkfill));
}

static void
initbeam(TkGridbeam *beam, int n)
{
	int i;
	memset(beam, 0, n * sizeof(TkGridbeam));
	for(i = 0; i < n; i++)
		beam[i].maxsize = 0x7fffffff;
}

static char*
ensuregridsize(TkGrid *grid, Point dim)
{
	TkGridcell **cells, *cellrow;
	TkGridbeam *cols, *rows;
	Point olddim;
	int i;
	olddim = grid->dim;
	if(dim.x < olddim.x)
		dim.x = olddim.x;
	if(dim.y < olddim.y)
		dim.y = olddim.y;
	if(dim.y > olddim.y){
		cells = realloc(grid->cells, sizeof(TkGridcell*)*dim.y);
		if(cells == nil)
			return TkNomem;
		grid->cells = cells;
		for(i = olddim.y; i < dim.y; i++){
			cells[i] = malloc(sizeof(TkGridcell)*dim.x);
			if(cells[i] == nil){
				for(i--; i >= olddim.y; i--)
					free(cells[i]);
				return TkNomem;
			}
		}
		rows = realloc(grid->rows, sizeof(TkGridbeam)*dim.y);
		if(rows == nil)
			return TkNomem;
		grid->rows = rows;
		initbeam(rows + olddim.y, dim.y - olddim.y);
		grid->dim.y = dim.y;
	}

	if(dim.x > olddim.x){
		/*
		 * any newly allocated rows will have the correct number of
		 * columns, so we don't need to reallocate them
		 */
		cells = grid->cells;
		for(i = 0; i < olddim.y; i++){
			cellrow = realloc(cells[i], sizeof(TkGridcell) * dim.x);
			if(cellrow == nil)
				return TkNomem;	/* leak some earlier rows, but not permanently */
			memset(cellrow + olddim.x, 0, (dim.x-olddim.x)*sizeof(TkGridcell));
			cells[i] = cellrow;
		}
		cols = realloc(grid->cols, sizeof(TkGridbeam)*dim.x);
		if(cols == nil)
			return TkNomem;
		initbeam(cols + olddim.x, dim.x - olddim.x);
		grid->cols = cols;
		grid->dim.x = dim.x;
	}
	return nil;
}

static TkGridbeam*
delbeams(TkGridbeam *beam, int nb, int x0, int x1)
{
	int i;
	TkGridbeam *b;
	for(i = x0; i < x1; i++)
		free(beam[i].name);
	memmove(&beam[x0], &beam[x1], sizeof(TkGridbeam) * (nb-x1));
	b = realloc(beam, sizeof(TkGridbeam) * (nb-(x1-x0)));
	return b ? b : beam;
}

static void
delrows(TkGrid *grid, int y0, int y1)
{
	TkGridcell **cells;
	memmove(grid->cells+y0, grid->cells+y1, sizeof(TkGridcell*) * (grid->dim.y-y1));
	grid->dim.y -= (y1 - y0);
	cells = realloc(grid->cells, sizeof(TkGridcell*) * grid->dim.y);
	if(cells != nil || grid->dim.y == 0)
		grid->cells = cells;		/* can realloc to a smaller size ever fail? */
}

static void
delcols(TkGrid *grid, int x0, int x1)
{
	TkGridcell **cells, *row;
	int y, ndx;
	Point dim;
	dim = grid->dim;
	ndx = dim.x - (x1 - x0);
	cells = grid->cells;
	for(y = 0; y < dim.y; y++){
		row = cells[y];
		memmove(row+x0, row+x1, sizeof(TkGridcell) * (dim.x - x1));
		row = realloc(row, sizeof(TkGridcell) * ndx);
		if(row != nil || ndx == 0)
			cells[y] = row;
	}
	grid->dim.x = ndx;
}

/*
 * insert items into rows/cols; the beam has already been expanded appropriately.
 */
void
insbeams(TkGridbeam *beam, int nb, int x, int n)
{
	memmove(&beam[x+n], &beam[x], sizeof(TkGridbeam)*(nb-x-n));
	initbeam(beam+x, n);
}

static char*
insrows(TkGrid *grid, int y0, int n)
{
	Point olddim;
	char *e;
	TkGridcell **cells, *tmp;
	int y;

	olddim = grid->dim;
	if(y0 > olddim.y){
		n = y0 + n - olddim.y;
		y0 = olddim.y;
	}

	e = ensuregridsize(grid, Pt(olddim.x, olddim.y + n));
	if(e != nil)
		return e;
	/*
	 * we know the extra rows will have been filled
	 * with blank, properly allocated rows, so just swap 'em with the
	 * ones that need moving.
	 */
	cells = grid->cells;
	for(y = olddim.y - 1; y >= y0; y--){
		tmp = cells[y + n];
		cells[y + n] = cells[y];
		cells[y] = tmp;
	}
	insbeams(grid->rows, grid->dim.y, y0, n);
	return nil;
}

static char*
inscols(TkGrid *grid, int x0, int n)
{
	TkGridcell **cells;
	Point olddim;
	int y;
	char *e;

	olddim = grid->dim;
	if(x0 > olddim.x){
		n = x0 + n - olddim.x;
		x0 = olddim.x;
	}

	e = ensuregridsize(grid, Pt(olddim.x + n, olddim.y));
	if(e != nil)
		return e;

	cells = grid->cells;
	for(y = 0; y < olddim.y; y++){
		memmove(cells[y] + x0 + n, cells[y] + x0, sizeof(TkGridcell) * (olddim.x - x0));
		memset(cells[y] + x0, 0, sizeof(TkGridcell) * n);
	}
	insbeams(grid->cols, grid->dim.x, x0, n);
	return nil;
}

static int
maximum(int a, int b)
{
	if(a > b)
		return a;
	return b;
}

/*
 * return the width of cols/rows between x0 and x1 in the beam,
 * excluding the padding at either end, but including padding in the middle.
 */
static int
beamsize(TkGridbeam *cols, int x0, int x1)
{
	int tot, fpad, x;

	if(x0 >= x1)
		return 0;

	tot = cols[x0].act;
	fpad = cols[x0].pad;
	for(x = x0 + 1; x < x1; x++){
		tot += cols[x].act + maximum(cols[x].pad, fpad);
		fpad = cols[x].pad;
	}
	return tot;
}

/*
 * return starting position of cell index on beam, relative
 * to top-left of grid
 */
static int
beamcellpos(TkGridbeam *beam, int blen, int index)
{
	int x;
	if(blen == 0 || index >= blen || index < 0)
		return 0;
	x = beam[0].pad + beamsize(beam, 0, index);
	if(index > 0)
		x += maximum(beam[index-1].pad, beam[index].pad);
	return x;
}

static Rectangle
cellbbox(TkGrid *grid, Point pos)
{
	Point dim;
	Rectangle r;

	dim = grid->dim;
	if(pos.x > dim.x)
		pos.x = dim.x;
	if(pos.y > dim.y)
		pos.y = dim.y;

	r.min.x = beamcellpos(grid->cols, dim.x, pos.x);
	r.min.y = beamcellpos(grid->rows, dim.y, pos.y);
	if(pos.x == dim.x)
		r.max.x = r.min.x;
	else
		r.max.x = r.min.x + grid->cols[pos.x].act;
	if(pos.y == dim.y)
		r.max.y = r.min.y;
	else
		r.max.y = r.min.y + grid->rows[pos.y].act;
	return rectaddpt(r, grid->origin);
}

/*
 * return true ifthere are any spanning cells covering row _index_
 */
static int
gridrowhasspan(TkGrid *grid, int index)
{
	int i, d;
	Point dim;
	TkGridcell *cell;

	dim = grid->dim;
	if(index > 0 && index < dim.y){
		for(i = 0; i < dim.x; i++){
			cell = &grid->cells[index][i];
			if(cell->tk != nil){
				d = cell->span.x;
				if(d == 0)
					return 1;
				i += d - 1;
			}
		}
	}
	return 0;
}

/*
 * return true ifthere are any spanning cells covering column _index_
 */
static int
gridcolhasspan(TkGrid *grid, int index)
{
	int i, d;
	Point dim;
	TkGridcell *cell;

	dim = grid->dim;
	if(index > 0 && index < dim.x){
		for(i = 0; i < dim.y; i++){
			cell = &grid->cells[i][index];
			if(cell->tk != nil){
				d = cell->span.y;
				if(d == 0)
					return 1;
				i += d - 1;
			}
		}
	}
	return 0;
}

/*
 * find cell that's spanning the grid position p
 */
static int
findspan(TkGrid *grid, Point p, Point *cp)
{
	Point dim;
	TkGridcell **cells;
	Tk *tk;

	dim = grid->dim;
	cells = grid->cells;

	if(p.x < 0 || p.y < 0 || p.x >= dim.x || p.y >= dim.y)
		return 0;

	if(cells[p.y][p.x].tk == nil)
		return 0;

	if(cells[p.y][p.x].span.x == 0){
		tk = cells[p.y][p.x].tk;
		for(; p.y >= 0; p.y--)
			if(cells[p.y][p.x].tk != tk)
				break;
		p.y++;
		for(; p.x >= 0; p.x--)
			if(cells[p.y][p.x].tk != tk)
				break;
		p.x++;
	}
	*cp = p;
	return 1;
}

static int
parsegridindex(TkGridbeam *beam, int blen, char *s)
{
	int n, i;
	char *e;

	if(s[0] == '\0')
		return -1;

	n = strtol(s, &e, 10);
	if(*e == '\0')
		return n;

	if(strcmp(s, "end") == 0)
		return blen;

	for(i = 0; i < blen; i++)
		if(beam[i].name != nil && strcmp(beam[i].name, s) == 0)
			return i;
	return -1;
}

static char*
tkgridconfigure(TkTop *t, TkGridparam *p, TkName *names)
{
	TkGrid *grid;
	TkGridcell **cells;
	TkName *n;
	Tk *tkf, *tkp;
	Point dim, pos, q, span, startpos;
	int maxcol, c, i, j, x;
	char *e;

	if(names == nil)
		return nil;

	if(p->span.x < 1 || p->span.y < 1)
		return TkBadvl;

	tkf = nil;

	maxcol = 0;
	for(n = names; n; n = n->link){
		c = n->name[0];
		if((c=='-' || c=='^' || c=='x') && n->name[1] == '\0'){
			maxcol++;
			continue;
		}
		tkp = tklook(t, n->name, 0);
		if(tkp == nil){
			tkerr(t, n->name);
			return TkBadwp;
		}
		if(tkp->flag & Tkwindow)
			return TkIstop;
		if(tkp->parent != nil)
			return TkWpack;
	
		/*
		 * unpacking now does give an non-reversible side effect
		 * ifthere's an error encountered later, but also means
		 * that a widget repacked in the same grid will
		 * have its original cell still available
		 */
		if(tkp->master != nil){
			tkpackqit(tkp->master);
			tkdelpack(tkp);
		}
		if(tkf == nil)
			tkf = tkp;
		n->obj = tkp;
		tkp->flag &= ~Tkgridpack;
		maxcol += p->span.x;
	}

	if(p->in == nil && tkf != nil)
		p->in = tklook(t, tkf->name->name, 1);

	if(p->in == nil)
		return TkNomaster;

	grid = p->in->grid;
	if(grid == nil && p->in->slave != nil)
		return TkNotgrid;

	if(grid == nil){
		grid = malloc(sizeof(TkGrid));
		if(grid == nil)
			return TkNomem;
		p->in->grid = grid;
	}

	dim = grid->dim;
	pos = ZP;
	if(p->row != nil){
		pos.y = parsegridindex(grid->rows, dim.y, p->row);
		if(pos.y < 0)
			return TkBadix;
	}
	if(p->col != nil){
		pos.x = parsegridindex(grid->cols, dim.x, p->col);
		if(pos.x < 0)
			return TkBadix;
	}
	/*
	 * ifrow is not specified, find first unoccupied row
	 */
	if(p->row == nil){
		for(pos.y = 0; pos.y < dim.y; pos.y++){
			for(x = 0; x < dim.x; x++)
				if(grid->cells[pos.y][x].tk != nil)
					break;
			if(x == dim.x)
				break;
		}
	}
	e = ensuregridsize(grid, Pt(pos.x + maxcol, pos.y + p->span.y));
	if(e != nil)
		return e;
	cells = grid->cells;

	startpos = pos;
	/*
	 * check that all our grid cells are empty, and that row/col spans
	 * are well formed
	 */
	n = names;
	while(n != nil){
		c = n->name[0];
		switch (c){
		case 'x':
			n = n->link;
			pos.x++;
			break;
		case '^':
			if(findspan(grid, Pt(pos.x, pos.y - 1), &q) == 0)
				return TkBadspan;
			span = cells[q.y][q.x].span;
			for(i = 0; i < span.x; i++){
				if(n == nil || strcmp(n->name, "^"))
					return TkBadspan;
				if(cells[pos.y][pos.x + i].tk != nil)
					return TkBadgridcell;
				n = n->link;
			}
			pos.x += span.x;
			break;
		case '-':
			return TkBadspan;
		case '.':
			tkp = n->obj;
			if(tkisslave(p->in, tkp))
				return TkRecur;
			n = n->link;
			if(tkp->flag & Tkgridpack)
				return TkWpack;
			tkp->flag |= Tkgridpack;
			span = p->span;
			for(; n != nil && strcmp(n->name, "-") == 0; n = n->link)
				span.x++;
			for(i = pos.x; i < pos.x + span.x; i++)
				for(j = pos.y; j < pos.y + span.y; j++)
					if(cells[j][i].tk != nil)
						return TkBadgridcell;
			pos.x = i;
			break; 
		}
	}

	/*
	 * actually insert the items into the grid
	 */
	n = names;
	pos = startpos;
	while(n != nil){
		c = n->name[0];
		switch (c){
		case 'x':
			n = n->link;
			pos.x++;
			break;
		case '^':
			findspan(grid, Pt(pos.x, pos.y - 1), &q);
			span = cells[q.y][q.x].span;
			tkf = cells[q.y][q.x].tk;
			if(q.y + span.y == pos.y)
				cells[q.y][q.x].span.y++;

			for(i = 0; i < span.x; i++){
				cells[pos.y][pos.x++].tk = tkf;
				n = n->link;
			}
			break;
		case '.':
			tkf = n->obj;
			n = n->link;
			span = p->span;
			for(; n != nil && strcmp(n->name, "-") == 0; n = n->link)
				span.x++;
			for(i = pos.x; i < pos.x + span.x; i++)
				for(j = pos.y; j < pos.y + span.y; j++)
					cells[j][i].tk = tkf;
			cells[pos.y][pos.x].span = span;
			tkf->master = p->in;
			tkf->next = p->in->slave;
			p->in->slave = tkf;
			if(p->in->flag & Tksubsub)
				tksetbits(tkf, Tksubsub);
			tkgridsetopt(p, tkf);
			pos.x = i;
			break; 
		}
	}
	tkpackqit(p->in);
	tkrunpack(t);
	return nil;
}

void
tkgriddelslave(Tk *tk)
{
	int y, x, yy;
	TkGrid *grid;
	TkGridcell **cells, *cell;
	Point dim, span;

	if(tk == nil || tk->master == nil || tk->master->grid == nil)
		return;
	grid = tk->master->grid;
	cells = grid->cells;
	dim = grid->dim;
	for(y = 0; y < dim.y; y++){
		for(x = 0; x < dim.x; x++){
			cell = &cells[y][x];
			if(cell->tk == tk){
				span = cell->span;
				for(yy = y; yy < y + span.y; yy++)
					memset(cells[yy] + x, 0, span.x * sizeof(TkGridcell));
				return;
			}
		}
	}
}

char*
tkgetgridmaster(TkTop *t, char **arg, char *buf, char *ebuf, Tk **master)
{
	TkGrid *grid;

	*arg = tkword(t, *arg, buf, ebuf, nil);
	*master = tklook(t, buf, 0);
	if(*master == nil)
		return TkBadwp;
	grid = (*master)->grid;
	if(grid == nil && (*master)->slave != nil)
		return TkNotgrid;
	return nil;
}

static int
gridfindloc(TkGridbeam *beam, int blen, int f)
{
	int x, i, fpad;
	if(blen == 0 || f < 0)
		return -1;

	fpad = 0;
	x =  0;
	for(i = 0; i < blen; i++){
		x += maximum(fpad, beam[i].pad);
		if(x <= f && f < x + beam[i].act)
			return i;
		x += beam[i].act;
	}
	return -1;
}

/*
 * optimised way to find a given slave, but somewhat more fragile
 * as it assumes the slave has already been placed on the grid.
 * not tested.
 */
static int
findslave(TkGrid *grid, Tk *tk, Point *pt)
{
	Point loc, dim, p;
	TkGridcell **cells;
	dim = grid->dim;
	cells = grid->cells;
	loc.x = gridfindloc(grid->cols, grid->dim.x, tk->act.x);
	if(loc.x == -1)
		loc.x = 0;
	loc.y = gridfindloc(grid->rows, grid->dim.y, tk->act.y);
	if(loc.y == -1)
		loc.y = 0;
	for(p.y = loc.y; p.y < dim.y; p.y++)
		for(p.x = loc.x; p.x < dim.x; p.x++)
			if(cells[p.y][p.x].tk == tk){
				*pt = p;
				return 1;
			}
	return 0;
}
static char*
tkgridcellinfo(TkTop *t, char *arg, char **val, char *buf, char *ebuf)
{
	/* grid cellinfo master x y */
	Tk *master;
	char *e;
	Point p;
	TkGrid *grid;
	TkGridcell **cells;

	e = tkgetgridmaster(t, &arg, buf, ebuf, &master);
	if(e != nil || master->grid == nil)
		return e;
	grid = master->grid;

	e = tkfracword(t, &arg, &p.x, nil);
	if(e != nil)
		return e;
	e = tkfracword(t, &arg, &p.y, nil);
	if(e != nil)
		return e;

	p.x = TKF2I(p.x);
	p.y = TKF2I(p.y);
	if(p.x < 0 || p.x >= grid->dim.x || p.y < 0 || p.y >= grid->dim.y)
		return nil;

	if(!findspan(grid, p, &p))
		return nil;

	cells = grid->cells;
	return tkvalue(val, "%s -in %s -column %d -row %d -columnspan %d -rowspan %d",
		cells[p.y][p.x].tk->name->name,
		cells[p.y][p.x].tk->master->name->name, p.x, p.y,
		cells[p.y][p.x].span.x, cells[p.y][p.x].span.y);
}

static char*
tkgridlocation(TkTop *t, char *arg, char **val, char *buf, char *ebuf)
{
	/* grid location master x y */
	Tk *master;
	char *e;
	Point p;
	int col, row;
	TkGrid *grid;

	e = tkgetgridmaster(t, &arg, buf, ebuf, &master);
	if(e != nil || master->grid == nil)
		return e;
	grid = master->grid;

	e = tkfracword(t, &arg, &p.x, nil);
	if(e != nil)
		return e;
	e = tkfracword(t, &arg, &p.y, nil);
	if(e != nil)
		return e;

	p.x = TKF2I(p.x);
	p.y = TKF2I(p.y);

	p = subpt(p, grid->origin);
	col = gridfindloc(grid->cols, grid->dim.x, p.x);
	row = gridfindloc(grid->rows, grid->dim.y, p.y);
	if(col < 0 || row < 0)
		return nil;
	return tkvalue(val, "%d %d", col, row);
}

static char*
tkgridinfo(TkTop *t, char *arg, char **val, char *buf, char *ebuf)
{
	Tk *tk;
	TkGrid *grid;
	int x, y;
	Point dim;
	TkGridcell *row;

	tkword(t, arg, buf, ebuf, nil);
	tk = tklook(t, buf, 0);
	if(tk == nil)
		return TkBadwp;
	if(tk->master == nil || tk->master->grid == nil)
		return TkNotgrid;
	grid = tk->master->grid;
	dim = grid->dim;
	for(y = 0; y < dim.y; y++){
		row = grid->cells[y];
		for(x = 0; x < dim.x; x++)
			if(row[x].tk == tk)
				goto Found;
	}
	return TkNotgrid;		/* should not happen */
Found:
	return tkvalue(val, "-in %s -column %d -row %d -columnspan %d -rowspan %d",
		tk->master->name->name, x, y, grid->cells[y][x].span.x, grid->cells[y][x].span.y);
}

static char*
tkgridforget(TkTop *t, char *arg, char *buf, char *ebuf)
{
	Tk *tk;
	for(;;){
		arg = tkword(t, arg, buf, ebuf, nil);
		if(arg == nil || buf[0] == '\0')
			break;
		tk = tklook(t, buf, 0);
		if(tk == nil){
			tkrunpack(t);
			tkerr(t, buf);
			return TkBadwp;
		}
		tkpackqit(tk->master);
		tkdelpack(tk);
	}
	tkrunpack(t);
	return nil;
}

static char*
tkgridslaves(TkTop *t, char *arg, char **val, char *buf, char *ebuf)
{
	Tk *master, *tk;
	char *fmt;
	int i, isrow, index;
	TkGrid *grid;
	TkGridcell *cell;
	char *e;
	e = tkgetgridmaster(t, &arg, buf, ebuf, &master);
	if(e != nil || master->grid == nil)
		return e;
	grid = master->grid;
	arg = tkword(t, arg, buf, ebuf, nil);
	fmt = "%s";
	if(buf[0] == '\0'){
		for(tk = master->slave; tk != nil; tk = tk->next){
			if(tk->name != nil){
				e = tkvalue(val, fmt, tk->name->name);
				if(e != nil)
					return e;
				fmt = " %s";
			}
		}
		return nil;
	}
	if(strcmp(buf, "-row") == 0)
		isrow = 1;
	else if(strcmp(buf, "-column") == 0)
		isrow = 0;
	else
		return TkBadop;
	tkword(t, arg, buf, ebuf, nil);
	if(isrow)
		index = parsegridindex(grid->rows, grid->dim.y, buf);
	else
		index = parsegridindex(grid->cols, grid->dim.x, buf);
	if(index < 0)
		return TkBadix;
	if(isrow){
		if(index >= grid->dim.y)
			return nil;
		for(i = 0; i < grid->dim.x; i++){
			cell = &grid->cells[index][i];
			if(cell->tk != nil && cell->span.x > 0 && cell->tk->name != nil){
				e = tkvalue(val, fmt, cell->tk->name->name);
				if(e != nil)
					return e;
				fmt = " %s";
			}
		}
	} else{
		if(index >= grid->dim.x)
			return nil;
		for(i = 0; i < grid->dim.y; i++){
			cell = &grid->cells[i][index];
			if(cell->tk != nil && cell->span.x > 0 && cell->tk->name != nil){
				e = tkvalue(val, fmt, cell->tk->name->name);
				if(e != nil)
					return e;
				fmt = " %s";
			}
		}
	}		

	return nil;
}

static char*
tkgriddelete(TkTop *t, char *arg, char *buf, char *ebuf, int delrow)
{
	Tk *master, **l, *f;
	TkGrid *grid;
	TkGridbeam *beam;
	int blen, i0, i1, x, y;
	Point dim;
	TkGridcell **cells;
	char *e;

	/*
	 * grid (columndelete|rowdelete) master index0 ?index1?
	 */

	e = tkgetgridmaster(t, &arg, buf, ebuf, &master);
	if(e != nil || master->grid == nil)
		return e;
	grid = master->grid;

	if(delrow){
		beam = grid->rows;
		blen = grid->dim.y;
	} else{
		beam = grid->cols;
		blen = grid->dim.x;
	}

	arg = tkword(t, arg, buf, ebuf, nil);
	i0 = parsegridindex(beam, blen, buf);
	if(i0 < 0)
		return TkBadix;

	tkword(t, arg, buf, ebuf, nil);
	if(buf[0] == '\0')
		i1 = i0 + 1;
	else
		i1 = parsegridindex(beam, blen, buf);
	if(i1 < 0 || i0 > i1)
		return TkBadix;
	if(i0 > blen || i0 == i1)
		return nil;
	if(i1 > blen)
		i1 = blen;
	cells = grid->cells;
	dim = grid->dim;
	if(delrow){
		if(gridrowhasspan(grid, i0) || gridrowhasspan(grid, i1))
			return TkBadgridcell;
		for(y = i0; y < i1; y++)
			for(x = 0; x < dim.x; x++)
				if(cells[y][x].tk != nil)
					cells[y][x].tk->flag |= Tkgridremove;
		delrows(grid, i0, i1);
		grid->rows = delbeams(beam, blen, i0, i1);
	} else{
		if(gridcolhasspan(grid, i0) || gridcolhasspan(grid, i1))
			return TkBadgridcell;
		for(y = 0; y < dim.y; y++)
			for(x = i0; x < i1; x++)
				if(cells[y][x].tk != nil)
					cells[y][x].tk->flag |= Tkgridremove;
		delcols(grid, i0, i1);
		grid->cols = delbeams(beam, blen, i0, i1);
	}
	l = &master->slave;
	for(f = *l; f; f = f->next){
		if(f->flag & Tkgridremove){
			*l = f->next;
			f->master = nil;
			f->flag &= ~Tkgridremove;
		} else
			l = &f->next;
	}
	tkpackqit(master);
	tkrunpack(t);
	return nil;
}


static char*
tkgridinsert(TkTop *t, char *arg, char *buf, char *ebuf, int insertrow)
{
	int index, count;
	Point dim;
	Tk *master;
	TkGrid *grid;
	int gotarg;
	char *e;

	/*
	 * grid (rowinsert|columninsert) master index ?count?
	 * it's an error ifthe insert splits any spanning cells.
	 */
	e = tkgetgridmaster(t, &arg, buf, ebuf, &master);
	if(e != nil || master->grid == nil)
		return e;
	grid = master->grid;
	dim = grid->dim;

	arg = tkword(t, arg, buf, ebuf, nil);
	if(insertrow)
		index = parsegridindex(grid->rows, dim.y, buf);
	else
		index = parsegridindex(grid->cols, dim.x, buf);
	if(index < 0 || index > (insertrow ? dim.y : dim.x))
		return TkBadix;

	tkword(t, arg, buf, ebuf, &gotarg);
	if(gotarg){
		count = strtol(buf, &buf, 10);
		if(buf[0] != '\0' || count < 0)
			return TkBadvl;
	} else
		count = 1;

	/*
	 * check that we're not splitting any spanning cells
	 */
	if(insertrow){
		if(gridrowhasspan(grid, index))
			return TkBadgridcell;
		e = insrows(grid, index, count);
	} else{
		if(gridcolhasspan(grid, index))
			return TkBadgridcell;
		e = inscols(grid, index, count);
	}
	tkpackqit(master);
	tkrunpack(t);
	return e;
}

/*
 * (rowconfigure|columnconfigure) master index ?-option value ...?
 */
static char*
tkbeamconfigure(TkTop *t, char *arg, int isrow)
{
	TkBeamparam p;
	TkOptab tko[2];
	TkName *names;
	Tk *master;
	int index;
	TkGrid *grid;
	TkGridbeam *beam;
	Point dim;
	char *e;

	p.equalise = BoolX;
	p.name = nil;
	p.weight = -1;
	p.minsize = -1;
	p.maxsize = -1;
	p.pad = -1;

	tko[0].ptr = &p;
	tko[0].optab = beamopts;
	tko[1].ptr = nil;

	names = nil;
	e = tkparse(t, arg, tko, &names);
	if(e != nil)
		return e;

	if(names == nil || names->link == nil)
		return TkBadvl;

	master = tklook(t, names->name, 0);
	if(master == nil)
		return TkBadwp;

	grid = master->grid;
	if(grid == nil){
		if(master->slave != nil)
			return TkNotgrid;
		grid = master->grid = malloc(sizeof(TkGrid));
		if(grid == nil){
			tkfreename(names);
			return TkNomem;
		}
	}

	if(isrow){
		index = parsegridindex(grid->rows, grid->dim.y, names->link->name);
	} else
		index = parsegridindex(grid->cols, grid->dim.x, names->link->name);
	if(index < 0){
		e = TkBadix;
		goto Error;
	}
	if(isrow)
		dim = Pt(grid->dim.x, index + 1);
	else
		dim = Pt(index + 1, grid->dim.y);
	e = ensuregridsize(grid, dim);
	if(e != nil)
		goto Error;

	if(isrow)
		beam = &grid->rows[index];
	else
		beam = &grid->cols[index];

	if(p.minsize >= 0)
		beam->minsize = p.minsize;
	if(p.maxsize >= 0)
		beam->maxsize = p.maxsize;
	if(p.weight >= 0)
		beam->weight = p.weight;
	if(p.pad >= 0)
		beam->pad = p.pad;
	if(p.name != nil){
		free(beam->name);
		beam->name = p.name;
	}
	if(p.equalise != BoolX)
		beam->equalise = p.equalise == BoolT;

	tkpackqit(master);
	tkrunpack(t);

Error:
	tkfreename(names);
	return e;
}

char*
tkgridsize(TkTop *t, char *arg, char **val, char *buf, char *ebuf)
{
	Tk *master;
	TkGrid *grid;
	char *e;

	e = tkgetgridmaster(t, &arg, buf, ebuf, &master);
	if(e != nil)
		return e;
	grid = master->grid;
	if(grid == nil)
		return tkvalue(val, "0 0");
	else
		return tkvalue(val, "%d %d", grid->dim.x, grid->dim.y);
}

char*
tkgridbbox(TkTop *t, char *arg, char **val, char *buf, char *ebuf)
{
	Point p0, p1;
	Tk *master;
	TkGrid *grid;
	char *e;
	int gotarg;
	Point dim;
	Rectangle r;

	e = tkgetgridmaster(t, &arg, buf, ebuf, &master);
	if(e != nil || master->grid == nil)
		return e;

	grid = master->grid;
	dim = grid->dim;
	arg = tkword(t, arg, buf, ebuf, &gotarg);
	if(!gotarg){
		p0 = ZP;
		p1 = dim;
	} else{
		p0.x = parsegridindex(grid->cols, dim.x, buf);
		arg = tkword(t, arg, buf, ebuf, &gotarg);
		if(!gotarg)
			return TkFewpt;
		p0.y = parsegridindex(grid->rows, dim.y, buf);
		arg = tkword(t, arg, buf, ebuf, &gotarg);
		if(!gotarg){
			p1 = p0;
		} else{
			p1.x = parsegridindex(grid->cols, dim.x, buf);
			arg = tkword(t, arg, buf, ebuf, &gotarg);
			if(!gotarg)
				return TkFewpt;
			p1.y = parsegridindex(grid->rows, dim.y, buf);
		}
	}
	if(p0.x < 0 || p0.y < 0 || p1.x < 0 || p1.y < 0)
		return TkBadix;

	r = cellbbox(grid, p0);
	if(!eqpt(p0, p1))
		combinerect(&r, cellbbox(grid, p1));
	return tkvalue(val, "%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

char*
tkgridindex(TkTop *t, char *arg, char **val, char *buf, char *ebuf, int isrow)
{
	Tk *master;
	TkGrid *grid;
	TkGridbeam *beam;
	int blen, i;

	arg = tkword(t, arg, buf, ebuf, nil);
	master = tklook(t, buf, 0);
	if(master == nil)
		return TkBadwp;
	tkword(t, arg, buf, ebuf, nil);
	grid = master->grid;
	if(grid == nil){
		beam = nil;
		blen = 0;
	} else if(isrow){
		beam = grid->rows;
		blen = grid->dim.y;
	} else{
		beam = grid->cols;
		blen = grid->dim.x;
	}
	i = parsegridindex(beam, blen, buf);
	if(i < 0)
		return TkBadix;
	return tkvalue(val, "%d", i);
}

void
tkfreegrid(TkGrid *grid)
{
	Point dim;
	int i;
	dim = grid->dim;
	for(i = 0; i < dim.x; i++)
		free(grid->cols[i].name);
	for(i = 0; i < dim.y; i++)
		free(grid->rows[i].name);
	for(i = 0; i < dim.y; i++)
		free(grid->cells[i]);
	free(grid->cells);
	free(grid->rows);
	free(grid->cols);
	free(grid);
}

char*
tkgrid(TkTop *t, char *arg, char **val)
{
	TkGridparam *p;
	TkOptab tko[2];
	TkName *names;
	char *e, *w, *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	w = tkword(t, arg, buf, buf+Tkmaxitem, nil);
	if('a' <= buf[0] && buf[0] <= 'z'){
		if(strcmp(buf, "debug") == 0){
			Tk *tk;
			e = tkgetgridmaster(t, &w, buf, buf+Tkmaxitem, &tk);
			if(e == nil)
				printgrid(tk->grid);
		} else
		if(strcmp(buf, "forget") == 0)
			e = tkgridforget(t, w, buf, buf+Tkmaxitem);
		else if(strcmp(buf, "propagate") == 0)
			e = tkpropagate(t, w);
		else if(strcmp(buf, "slaves") == 0)
			e = tkgridslaves(t, w, val, buf, buf+Tkmaxitem);
		else if(strcmp(buf, "rowconfigure") == 0)
			e = tkbeamconfigure(t, w, 1);
		else if(strcmp(buf, "columnconfigure") == 0)
			e = tkbeamconfigure(t, w, 0);
		else if(strcmp(buf, "rowinsert") == 0)
			e = tkgridinsert(t, w, buf, buf+Tkmaxitem, 1);
		else if(strcmp(buf, "columninsert") == 0)
			e = tkgridinsert(t, w, buf, buf+Tkmaxitem, 0);
		else if(strcmp(buf, "size") == 0)
			e = tkgridsize(t, w, val, buf, buf+Tkmaxitem);
		else if(strcmp(buf, "rowdelete") == 0)
			e = tkgriddelete(t, w, buf, buf+Tkmaxitem, 1);
		else if(strcmp(buf, "columndelete") == 0)
			e = tkgriddelete(t, w, buf, buf+Tkmaxitem, 0);
		else if(strcmp(buf, "rowindex") == 0)
			e = tkgridindex(t, w, val, buf, buf+Tkmaxitem, 1);
		else if(strcmp(buf, "columnindex") == 0)
			e = tkgridindex(t, w, val, buf, buf+Tkmaxitem, 0);
		else if(strcmp(buf, "bbox") == 0)
			e = tkgridbbox(t, w, val, buf, buf+Tkmaxitem);
		else if(strcmp(buf, "location") == 0)
			e = tkgridlocation(t, w, val, buf, buf+Tkmaxitem);
		else if(strcmp(buf, "cellinfo") == 0)
			e = tkgridcellinfo(t, w, val, buf, buf+Tkmaxitem);
		else if(strcmp(buf, "info") == 0)
			e = tkgridinfo(t, w, val, buf, buf+Tkmaxitem);
		else{
			tkerr(t, buf);
			e = TkBadcm;
		}
	} else{
		p = malloc(sizeof(TkGridparam));
		if(p == nil)
			return TkNomem;
		tko[0].ptr = p;
		tko[0].optab = opts;
		tko[1].ptr = nil;
	
		p->span.x = 1;
		p->span.y = 1;
		p->pad.x = p->pad.y = p->ipad.x = p->ipad.y = -1;
		p->sticky = -1;
	
		names = nil;
		e = tkparse(t, arg, tko, &names);
		if(e != nil){
			free(p);
			return e;
		}
	
		e = tkgridconfigure(t, p, names);
		free(p->row);
		free(p->col);
		free(p);
		tkfreename(names);
	}
	free(buf);
	return e;
}

/*
 * expand widths of rows/columns according to weight.
 * return amount of space still left over.
 */
static int
expandwidths(int x0, int x1, int totwidth, TkGridbeam *cols, int expandzero)
{
	int share, x, slack, m, w, equal;

	if(x0 >= x1)
		return 0;

	share = 0;
	for(x = x0; x < x1; x++)
		share += cols[x].weight;

	slack = totwidth - beamsize(cols, x0, x1);
	if(slack <= 0)
		return 0;

	if(share == 0 && expandzero){
		share = x1 - x0;
		equal = 1;
	} else
		equal = 0;

	for(x = x0; x < x1 && share > 0 ; x++){
		w = equal ? 1 : cols[x].weight;
		m = slack * w / share;
		cols[x].act += m;
		slack -= m;
		share -= w;
	}
	return slack;
}

static void
gridequalise(TkGridbeam *beam, int blen)
{
	int i, max;

	max = 0;
	for(i = 0; i < blen; i++)
		if(beam[i].equalise == BoolT && beam[i].act > max)
			max = beam[i].act;

	if(max > 0)
		for(i = 0; i < blen; i++)
			if(beam[i].equalise == BoolT)
				beam[i].act = max;
}

/*
 * take into account min/max beam sizes.
 * max takes precedence
 */
static void
beamminmax(TkGridbeam *beam, int n)
{
	TkGridbeam *e;
	e = &beam[n];
	for(; beam < e; beam++){
		if(beam->act < beam->minsize)
			beam->act = beam->minsize;
		if(beam->act > beam->maxsize)
			beam->act = beam->maxsize;
	}
}

int
tkgridder(Tk *master)
{
	TkGrid *grid;
	TkGridcell **cells, *cell;
	TkGridbeam *rows, *cols;
	TkGeom pos;
	Point org;
	Tk *slave;
	int dx, dy, x, y, w, bw2, fpadx, fpady;
	Point req;

	grid = master->grid;
	dx = grid->dim.x;
	dy = grid->dim.y;
	cells = grid->cells;
	rows = grid->rows;
	cols = grid->cols;

	for(x = 0; x < dx; x++)
		cols[x].act = 0;

	/* calculate column widths and row heights (ignoring multi-column cells) */
	for(y = 0; y < dy; y++){
		rows[y].act = 0;
		for(x = 0; x < dx; x++){
			cell = &cells[y][x];
			if((slave = cell->tk) != nil){
				bw2 = slave->borderwidth * 2;
				w = slave->req.width + bw2 + slave->pad.x + slave->ipad.x;
				if(cell->span.x == 1 && w > cols[x].act)
					cols[x].act = w;
				w = slave->req.height + bw2 + slave->pad.y + slave->ipad.y;
				if(cell->span.y == 1 && w > rows[y].act)
					rows[y].act = w;
			}
		}
	}

	beamminmax(rows, dy);
	beamminmax(cols, dx);

	/* now check that spanning cells fit in their rows/columns */
	for(y = 0; y < dy; y++)
		for(x = 0; x < dx; x++){
			cell = &cells[y][x];
			if((slave = cell->tk) != nil){
				bw2 = slave->borderwidth * 2;
				if(cell->span.x > 1){
					w = slave->req.width + bw2 + slave->pad.x + slave->ipad.x;
					expandwidths(x, x+cell->span.x, w, cols, 1);
				}
				if(cell->span.y > 1){
					w = slave->req.height + bw2 + slave->pad.y + slave->ipad.y;
					expandwidths(y, y+cell->span.y, w, rows, 1);
				}
			}
		}

	gridequalise(rows, dy);
	gridequalise(cols, dx);

	if(dx == 0)
		req.x = 0;
	else
		req.x = beamsize(cols, 0, dx) + cols[0].pad + cols[dx-1].pad;

	if(dy == 0)
		req.y = 0;
	else
		req.y = beamsize(rows, 0, dy) + rows[0].pad + rows[dy-1].pad;

	if(req.x != master->req.width || req.y != master->req.height)
	if((master->flag & Tknoprop) == 0){
		if(master->geom != nil){
			master->geom(master, master->act.x, master->act.y, 
					req.x, req.y);
		} else{
			master->req.width = req.x;
			master->req.height = req.y;
			tkpackqit(master->master);
		}
		return 0;
    	}
	org = ZP;
	if(dx > 0 && master->act.width > req.x)
		org.x = expandwidths(0, dx,
				master->act.width - (cols[0].pad + cols[dx-1].pad),
				cols, 0) / 2;
	if(dy > 0 && master->act.height > req.y)
		org.y = expandwidths(0, dy,
				master->act.height - (rows[0].pad + rows[dy-1].pad),
				rows, 0) / 2;

	grid->origin = org;
	pos.y = org.y;
	fpady = 0;
	for(y = 0; y < dy; y++){
		pos.y += maximum(fpady, rows[y].pad);
		fpady = rows[y].pad;

		pos.x = org.x;
		fpadx = 0;
		for(x = 0; x < dx; x++){
			cell = &cells[y][x];
			pos.x += maximum(fpadx, cols[x].pad);
			fpadx = cols[x].pad;
			if((slave = cell->tk) != nil && cell->span.x > 0){
				pos.width = beamsize(cols, x, x + cell->span.x);
				pos.height = beamsize(rows, y, y + cell->span.y);
				tksetslavereq(slave, pos);
			}
			pos.x += cols[x].act;
		}
		pos.y += rows[y].act;
	}

	master->dirty = tkrect(master, 1);
	tkdirty(master);
	return 1;
}
