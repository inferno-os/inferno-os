implement Columnm;

include "common.m";

sys : Sys;
utils : Utils;
drawm : Draw;
acme : Acme;
graph : Graph;
gui : Gui;
dat : Dat;
textm : Textm;
rowm : Rowm;
filem : Filem;
windowm : Windowm;

FALSE, TRUE, XXX : import Dat;
Border : import Dat;
mouse, colbutton : import dat;
Point, Rect, Image : import drawm;
draw : import graph;
min, max, abs, error, clearmouse : import utils;
black, white, mainwin : import gui;
Text : import textm;
Row : import rowm;
Window : import windowm;
File : import filem;
Columntag : import Textm;
BACK : import Framem;
tagcols, textcols : import acme;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	dat = mods.dat;
	utils = mods.utils;
	drawm = mods.draw;
	acme = mods.acme;
	graph = mods.graph;
	gui = mods.gui;
	textm = mods.textm;
	rowm = mods.rowm;
	filem = mods.filem;
	windowm = mods.windowm;
}

Column.init(c : self ref Column, r : Rect)
{
	r1 : Rect;
	t : ref Text;
	dummy : ref File = nil;

	draw(mainwin, r, white, nil, (0, 0));
	c.r = r;
	c.row = nil;
	c.w = nil;
	c.nw = 0;
	c.tag = textm->newtext();
	t = c.tag;
	t.w = nil;
	t.col = c;
	r1 = r;
	r1.max.y = r1.min.y + (graph->font).height;
	t.init(dummy.addtext(t), r1, dat->reffont, tagcols);
	t.what = Columntag;
	r1.min.y = r1.max.y;
	r1.max.y += Border;
	draw(mainwin, r1, black, nil, (0, 0));
	t.insert(0, "New Cut Paste Snarf Sort Zerox Delcol ", 38, TRUE, 0);
	t.setselect(t.file.buf.nc, t.file.buf.nc);
	draw(mainwin, t.scrollr, colbutton, nil, colbutton.r.min);
	c.safe = TRUE;
}

Column.add(c : self ref Column, w : ref Window, clone : ref Window, y : int) : ref Window
{
	r, r1 : Rect;
	v : ref Window;
	i, t : int;

	v = nil;
	r = c.r;
	r.min.y = c.tag.frame.r.max.y+Border;
	if(y<r.min.y && c.nw>0){	# steal half of last window by default 
		v = c.w[c.nw-1];
		y = v.body.frame.r.min.y+v.body.frame.r.dy()/2;
	}
	# look for window we'll land on 
	for(i=0; i<c.nw; i++){
		v = c.w[i];
		if(y < v.r.max.y)
			break;
	}
	if(c.nw > 0){
		if(i < c.nw)
			i++;	# new window will go after v 
		#
		# if v's too small, grow it first.
		#
		 
		if(!c.safe || v.body.frame.maxlines<=3){
			c.grow(v, 1, 1);
			y = v.body.frame.r.min.y+v.body.frame.r.dy()/2;
		}
		r = v.r;
		if(i == c.nw)
			t = c.r.max.y;
		else
			t = c.w[i].r.min.y-Border;
		r.max.y = t;
		draw(mainwin, r, textcols[BACK], nil, (0, 0));
		r1 = r;
		y = min(y, t-(v.tag.frame.font.height+v.body.frame.font.height+Border+1));
		r1.max.y = min(y, v.body.frame.r.min.y+v.body.frame.nlines*v.body.frame.font.height);
		r1.min.y = v.reshape(r1, FALSE);
		r1.max.y = r1.min.y+Border;
		draw(mainwin, r1, black, nil, (0, 0));
		r.min.y = r1.max.y;
	}
	if(w == nil){
		w = ref Window;
		draw(mainwin, r, textcols[BACK], nil, (0, 0));
		w.col = c;
		w.init(clone, r);
	}else{
		w.col = c;
		w.reshape(r, FALSE);
	}
	w.tag.col = c;
	w.tag.row = c.row;
	w.body.col = c;
	w.body.row = c.row;
	ocw := c.w;
	c.w = array[c.nw+1] of ref Window;
	c.w[0:] = ocw[0:i];
	c.w[i+1:] = ocw[i:c.nw];
	ocw = nil;
	c.nw++;
	c.w[i] = w;
	utils->savemouse(w);
	# near but not on the button 
	graph->cursorset(w.tag.scrollr.max.add(Point(3, 3)));
	dat->barttext = w.body;
	c.safe = TRUE;
	return w;
}

Column.close(c : self ref Column, w : ref Window, dofree : int)
{
	r : Rect;
	i : int;

	# w is locked 
	if(!c.safe)
		c.grow(w, 1, 1);
	for(i=0; i<c.nw; i++)
		if(c.w[i] == w)
			break;
	if (i == c.nw)
		error("can't find window");
	r = w.r;
	w.tag.col = nil;
	w.body.col = nil;
	w.col = nil;
	utils->restoremouse(w);
	if(dofree){
		w.delete();
		w.close();
	}
	ocw := c.w;
	c.w = array[c.nw-1] of ref Window;
	c.w[0:] = ocw[0:i];
	c.w[i:] = ocw[i+1:c.nw];
	ocw = nil;
	c.nw--;
	if(c.nw == 0){
		draw(mainwin, r, white, nil, (0, 0));
		return;
	}
	if(i == c.nw){		# extend last window down 
		w = c.w[i-1];
		r.min.y = w.r.min.y;
		r.max.y = c.r.max.y;
	}else{			# extend next window up 
		w = c.w[i];
		r.max.y = w.r.max.y;
	}
	draw(mainwin, r, textcols[BACK], nil, (0, 0));
	if(c.safe)
		w.reshape(r, FALSE);
}

Column.closeall(c : self ref Column)
{
	i : int;
	w : ref Window;

	if(c == dat->activecol)
		dat->activecol = nil;
	c.tag.close();
	for(i=0; i<c.nw; i++){
		w = c.w[i];
		w.close();
	}
	c.nw = 0;
	c.w = nil;
	c = nil;
	clearmouse();
}

Column.mousebut(c : self ref Column)
{
	graph->cursorset(c.tag.scrollr.min.add(c.tag.scrollr.max).div(2));
}

Column.reshape(c : self ref Column, r : Rect)
{
	i : int;
	r1, r2 : Rect;
	w : ref Window;

	clearmouse();
	r1 = r;
	r1.max.y = r1.min.y + c.tag.frame.font.height;
	c.tag.reshape(r1);
	draw(mainwin, c.tag.scrollr, colbutton, nil, colbutton.r.min);
	r1.min.y = r1.max.y;
	r1.max.y += Border;
	draw(mainwin, r1, black, nil, (0, 0));
	r1.max.y = r.max.y;
	for(i=0; i<c.nw; i++){
		w = c.w[i];
		w.maxlines = 0;
		if(i == c.nw-1)
			r1.max.y = r.max.y;
		else
			r1.max.y = r1.min.y+(w.r.dy()+Border)*r.dy()/c.r.dy();
		r2 = r1;
		r2.max.y = r2.min.y+Border;
		draw(mainwin, r2, black, nil, (0, 0));
		r1.min.y = r2.max.y;
		r1.min.y = w.reshape(r1, FALSE);
	}
	c.r = r;
}

colcmp(a : ref Window, b : ref Window) : int
{
	r1, r2 : string;

	r1 = a.body.file.name;
	r2 = b.body.file.name;
	if (r1 < r2)
		return -1;
	if (r1 > r2)
		return 1;
	return 0;
}

qsort(a : array of ref Window, n : int)
{
	i, j : int;
	t : ref Window;

	while(n > 1) {
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;) {
			do
				i++;
			while(i < n && colcmp(a[i], a[0]) < 0);
			do
				j--;
			while(j > 0 && colcmp(a[j], a[0]) > 0);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n) {
			qsort(a, j);
			a = a[j+1:];
		} else {
			qsort(a[j+1:], n);
			n = j;
		}
	}
}

Column.sort(c : self ref Column)
{
	i, y : int;
	r, r1 : Rect;
	rp : array of Rect;
	w : ref Window;
	wp : array of ref Window;

	if(c.nw == 0)
		return;
	clearmouse();
	rp = array[c.nw] of Rect;
	wp = array[c.nw] of ref Window;
	wp[0:] = c.w[0:c.nw];
	qsort(wp, c.nw);
	for(i=0; i<c.nw; i++)
		rp[i] = wp[i].r;
	r = c.r;
	r.min.y = c.tag.frame.r.max.y;
	draw(mainwin, r, textcols[BACK], nil, (0, 0));
	y = r.min.y;
	for(i=0; i<c.nw; i++){
		w = wp[i];
		r.min.y = y;
		if(i == c.nw-1)
			r.max.y = c.r.max.y;
		else
			r.max.y = r.min.y+w.r.dy()+Border;
		r1 = r;
		r1.max.y = r1.min.y+Border;
		draw(mainwin, r1, black, nil, (0, 0));
		r.min.y = r1.max.y;
		y = w.reshape(r, FALSE);
	}
	rp = nil;
	c.w = wp;
}

Column.grow(c : self ref Column, w : ref Window, but : int, mv : int)
{
	r, cr : Rect;
	i, j, k, l, y1, y2, tot, nnl, onl, dnl, h : int;
	nl, ny : array of int;
	v : ref Window;

	for(i=0; i<c.nw; i++)
		if(c.w[i] == w)
			break;
	if (i == c.nw)
		error("can't find window");

	cr = c.r;
	if(but < 0){	# make sure window fills its own space properly 
		r = w.r;
		if(i == c.nw-1)
			r.max.y = cr.max.y;
		else
			r.max.y = c.w[i+1].r.min.y;
		w.reshape(r, FALSE);
		return;
	}
	cr.min.y = c.w[0].r.min.y;
	if(but == 3){	# full size 
		if(i != 0){
			v = c.w[0];
			c.w[0] = w;
			c.w[i] = v;
		}
		draw(mainwin, cr, textcols[BACK], nil, (0, 0));
		w.reshape(cr, FALSE);
		for(i=1; i<c.nw; i++)
			c.w[i].body.frame.maxlines = 0;
		c.safe = FALSE;
		return;
	}
	# store old #lines for each window 
	onl = w.body.frame.maxlines;
	nl = array[c.nw] of int;
	ny = array[c.nw] of int;
	tot = 0;
	for(j=0; j<c.nw; j++){
		l = c.w[j].body.frame.maxlines;
		nl[j] = l;
		tot += l;
	}
	# approximate new #lines for this window 
	if(but == 2){	# as big as can be 
		for (j = 0; j < c.nw; j++)
			nl[j] = 0;
		nl[i] = tot;
	}
	else {
		nnl = min(onl + max(min(5, w.maxlines), onl/2), tot);
		if(nnl < w.maxlines)
			nnl = (w.maxlines+nnl)/2;
		if(nnl == 0)
			nnl = 2;
		dnl = nnl - onl;
		# compute new #lines for each window 
		for(k=1; k<c.nw; k++){
			# prune from later window 
			j = i+k;
			if(j<c.nw && nl[j]){
				l = min(dnl, max(1, nl[j]/2));
				nl[j] -= l;
				nl[i] += l;
				dnl -= l;
			}
			# prune from earlier window 
			j = i-k;
			if(j>=0 && nl[j]){
				l = min(dnl, max(1, nl[j]/2));
				nl[j] -= l;
				nl[i] += l;
				dnl -= l;
			}
		}
	}
	# pack everyone above 
	y1 = cr.min.y;
	for(j=0; j<i; j++){
		v = c.w[j];
		r = v.r;
		r.min.y = y1;
		r.max.y = y1+v.tag.all.dy();
		if(nl[j])
			r.max.y += 1 + nl[j]*v.body.frame.font.height;
		if(!c.safe || !v.r.eq(r)){
			draw(mainwin, r, textcols[BACK], nil, (0, 0));
			v.reshape(r, c.safe);
		}
		r.min.y = v.r.max.y;
		r.max.y += Border;
		draw(mainwin, r, black, nil, (0, 0));
		y1 = r.max.y;
	}
	# scan to see new size of everyone below 
	y2 = c.r.max.y;
	for(j=c.nw-1; j>i; j--){
		v = c.w[j];
		r = v.r;
		r.min.y = y2-v.tag.all.dy();
		if(nl[j])
			r.min.y -= 1 + nl[j]*v.body.frame.font.height;
		r.min.y -= Border;
		ny[j] = r.min.y;
		y2 = r.min.y;
	}
	# compute new size of window 
	r = w.r;
	r.min.y = y1;
	r.max.y = r.min.y+w.tag.all.dy();
	h = w.body.frame.font.height;
	if(y2-r.max.y >= 1+h+Border){
		r.max.y += 1;
		r.max.y += h*((y2-r.max.y)/h);
	}
	# draw window 
	if(!c.safe || !w.r.eq(r)){
		draw(mainwin, r, textcols[BACK], nil, (0, 0));
		w.reshape(r, c.safe);
	}
	if(i < c.nw-1){
		r.min.y = r.max.y;
		r.max.y += Border;
		draw(mainwin, r, black, nil, (0, 0));
		for(j=i+1; j<c.nw; j++)
			ny[j] -= (y2-r.max.y);
	}
	# pack everyone below 
	y1 = r.max.y;
	for(j=i+1; j<c.nw; j++){
		v = c.w[j];
		r = v.r;
		r.min.y = y1;
		r.max.y = y1+v.tag.all.dy();
		if(nl[j])
			r.max.y += 1 + nl[j]*v.body.frame.font.height;
		if(!c.safe || !v.r.eq(r)){
			draw(mainwin, r, textcols[BACK], nil, (0, 0));
			v.reshape(r, c.safe);
		}
		if(j < c.nw-1){	# no border on last window 
			r.min.y = v.r.max.y;
			r.max.y += Border;
			draw(mainwin, r, black, nil, (0, 0));
		}
		y1 = r.max.y;
	}
	r = w.r;
	r.min.y = y1;
	r.max.y = c.r.max.y;
	draw(mainwin, r, textcols[BACK], nil, (0, 0));
	nl = nil;
	ny = nil;
	c.safe = TRUE;
	if (mv)
		w.mousebut();
}

Column.dragwin(c : self ref Column, w : ref Window, but : int)
{
	r : Rect;
	i, b : int;
	p, op : Point;
	v : ref Window;
	nc : ref Column;

	clearmouse();
	graph->cursorswitch(dat->boxcursor);
	b = mouse.buttons;
	op = mouse.xy;
	while(mouse.buttons == b)
		acme->frgetmouse();
	graph->cursorswitch(dat->arrowcursor);
	if(mouse.buttons){
		while(mouse.buttons)
			acme->frgetmouse();
		return;
	}

	for(i=0; i<c.nw; i++)
		if(c.w[i] == w)
			break;
	if (i == c.nw)
		error("can't find window");

	p = mouse.xy;
	if(abs(p.x-op.x)<5 && abs(p.y-op.y)<5){
		c.grow(w, but, 1);
		w.mousebut();
		return;
	}
	# is it a flick to the right? 
	if(abs(p.y-op.y)<10 && p.x>op.x+30 && c.row.whichcol(p) == c)
		p.x += w.r.dx();	# yes: toss to next column 
	nc = c.row.whichcol(p);
	if(nc!=nil && nc!=c){
		c.close(w, FALSE);
		nc.add(w, nil, p.y);
		w.mousebut();
		return;
	}
	if(i==0 && c.nw==1)
		return;			# can't do it 
	if((i>0 && p.y<c.w[i-1].r.min.y) || (i<c.nw-1 && p.y>w.r.max.y)
	|| (i==0 && p.y>w.r.max.y)){
		# shuffle 
		c.close(w, FALSE);
		c.add(w, nil, p.y);
		w.mousebut();
		return;
	}
	if(i == 0)
		return;
	v = c.w[i-1];
	if(p.y < v.tag.all.max.y)
		p.y = v.tag.all.max.y;
	if(p.y > w.r.max.y-w.tag.all.dy()-Border)
		p.y = w.r.max.y-w.tag.all.dy()-Border;
	r = v.r;
	r.max.y = p.y;
	if(r.max.y > v.body.frame.r.min.y){
		r.max.y -= (r.max.y-v.body.frame.r.min.y)%v.body.frame.font.height;
		if(v.body.frame.r.min.y == v.body.frame.r.max.y)
			r.max.y++;
	}
	if(!r.eq(v.r)){
		draw(mainwin, r, textcols[BACK], nil, (0, 0));
		v.reshape(r, c.safe);
	}
	r.min.y = v.r.max.y;
	r.max.y = r.min.y+Border;
	draw(mainwin, r, black, nil, (0, 0));
	r.min.y = r.max.y;
	if(i == c.nw-1)
		r.max.y = c.r.max.y;
	else
		r.max.y = c.w[i+1].r.min.y-Border;
	# r.max.y = w.r.max.y;
	if(!r.eq(w.r)){
		draw(mainwin, r, textcols[BACK], nil, (0, 0));
		w.reshape(r, c.safe);
	}
	c.safe = TRUE;
    	w.mousebut();
}

Column.which(c : self ref Column, p : Point) : ref Text
{
	i : int;
	w : ref Window;

	if(!p.in(c.r))
		return nil;
	if(p.in(c.tag.all))
		return c.tag;
	for(i=0; i<c.nw; i++){
		w = c.w[i];
		if(p.in(w.r)){
			if(p.in(w.tag.all))
				return w.tag;
			return w.body;
		}
	}
	return nil;
}

Column.clean(c : self ref Column, exiting : int) : int
{
	clean : int;
	i : int;

	clean = TRUE;
	for(i=0; i<c.nw; i++)
		clean &= c.w[i].clean(TRUE, exiting);
	return clean;
}
